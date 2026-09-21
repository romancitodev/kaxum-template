use std::time::Duration;

use axum::{Router, extract::State, http::StatusCode, routing::get};
use sqlx::PgPool;
use tokio::{sync::watch, time::timeout};

use crate::{
  app::App,
  monitor::redis::{RedisInfo, RedisStatus},
};

const POSTGRES_CHECK_TIMEOUT: Duration = Duration::from_secs(2);

pub fn router() -> Router<App> {
  Router::new()
    .route("/health/live", get(live))
    .route("/health/ready", get(ready))
    .route("/health/startup", get(startup))
}

/// El proceso está vivo. No toca ninguna dependencia externa.
async fn live() -> StatusCode {
  StatusCode::OK
}

/// La inicialización terminó. `App::new` corre antes de abrir el puerto,
/// así que si este handler responde, la app ya arrancó.
async fn startup() -> StatusCode {
  StatusCode::OK
}

/// Solo PostgreSQL es dependencia dura: si no responde, el pod sale de rotación.
/// Redis es caché, así que si está caído el pod sigue ready (200) y solo se
/// reporta como degradado en el cuerpo. El estado sale del heartbeat en
/// background, sin tocar la red.
async fn ready(
  State(db): State<PgPool>,
  State(redis_info): State<watch::Receiver<RedisInfo>>,
) -> (StatusCode, String) {
  match timeout(POSTGRES_CHECK_TIMEOUT, sqlx::query("SELECT 1").execute(&db)).await {
    Ok(Ok(_)) => {}
    Ok(Err(err)) => {
      tracing::error!("Postgres readiness check failed: {err}");
      return (
        StatusCode::SERVICE_UNAVAILABLE,
        "postgres unavailable".into(),
      );
    }
    Err(_) => {
      tracing::error!("Postgres readiness check timed out");
      return (StatusCode::SERVICE_UNAVAILABLE, "postgres timed out".into());
    }
  }

  let redis = *redis_info.borrow();
  match redis.status {
    RedisStatus::Up => (StatusCode::OK, "ready".into()),
    RedisStatus::Down { since } => (
      StatusCode::OK,
      format!(
        "ready (degraded: redis down for {}s)",
        since.elapsed().as_secs()
      ),
    ),
  }
}

#[cfg(test)]
mod tests {
  use tokio::time::Instant;

  use super::*;

  // Ejemplo de test con Postgres real: `#[sqlx::test]` crea una base temporal a partir de
  // DATABASE_URL, le aplica `migrations/`, te pasa el pool y la borra al terminar.
  #[sqlx::test]
  async fn ready_with_postgres_up(pool: PgPool) {
    let (_tx, rx) = watch::channel(RedisInfo {
      status: RedisStatus::Up,
      last_heartbeat: Instant::now(),
    });

    let (status, body) = ready(State(pool), State(rx)).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, "ready");
  }
}
