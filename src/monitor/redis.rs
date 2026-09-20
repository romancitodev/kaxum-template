use std::time::Duration;

use redis::aio::ConnectionManager;
use tokio::{
  sync::watch,
  time::{Instant, MissedTickBehavior, interval, timeout},
};

const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Clone, Copy, Debug)]
pub enum RedisStatus {
  Up,
  Down { since: Instant },
}

/// Último estado conocido de Redis, actualizado por el heartbeat en background.
#[derive(Clone, Copy, Debug)]
pub struct RedisInfo {
  pub status: RedisStatus,
  /// Último PING exitoso.
  pub last_heartbeat: Instant,
}

/// Lanza la task que hace PING periódicamente y devuelve un receptor de solo
/// lectura: los handlers leen el último estado sin tocar Redis.
///
/// La task muere sola cuando termina el runtime, o cuando se dropean todos los
/// receptores.
pub fn spawn(mut conn: ConnectionManager) -> watch::Receiver<RedisInfo> {
  // `ConnectionManager::new` ya conectó, así que arrancamos en `Up`.
  let (tx, rx) = watch::channel(RedisInfo {
    status: RedisStatus::Up,
    last_heartbeat: Instant::now(),
  });

  tokio::spawn(async move {
    let mut tick = interval(HEARTBEAT_INTERVAL);
    tick.set_missed_tick_behavior(MissedTickBehavior::Delay);

    while !tx.is_closed() {
      tick.tick().await;

      let ping = timeout(
        HEARTBEAT_TIMEOUT,
        redis::cmd("PING").query_async::<String>(&mut conn),
      )
      .await;
      let ok = matches!(ping, Ok(Ok(_)));

      tx.send_modify(|info| {
        let now = Instant::now();
        match (ok, info.status) {
          (true, RedisStatus::Up) => info.last_heartbeat = now,
          (true, RedisStatus::Down { since }) => {
            tracing::info!("Redis recovered after {:?}", since.elapsed());
            *info = RedisInfo {
              status: RedisStatus::Up,
              last_heartbeat: now,
            };
          }
          (false, RedisStatus::Up) => {
            tracing::warn!("Redis heartbeat failed: {ping:?}");
            info.status = RedisStatus::Down { since: now };
          }
          (false, RedisStatus::Down { .. }) => {}
        }
      });
    }
  });

  rx
}
