use std::time::Duration;

use anyhow::Context;
use axum::extract::FromRef;
use futures::{TryFutureExt, try_join};
use redis::{Client, aio::ConnectionManager};
use sqlx::{PgPool, postgres::PgPoolOptions};
use tokio::sync::watch;

use crate::{
  config::Config,
  monitor::{self, redis::RedisInfo},
};

#[derive(Clone, FromRef)]
pub struct App {
  pub db: PgPool,
  pub redis: ConnectionManager,
  pub redis_info: watch::Receiver<RedisInfo>,
}

impl App {
  pub async fn new(config: &Config) -> anyhow::Result<Self> {
    let redis_client = Client::open(config.redis_url.as_str()).context("REDIS_URL inválida")?;

    let db = PgPoolOptions::new()
      .max_connections(10)
      .acquire_timeout(secs(5))
      .connect(&config.database_url)
      .map_err(|err| anyhow::Error::new(err).context("Can't initialize Postgres"));
    let redis = ConnectionManager::new(redis_client)
      .map_err(|err| anyhow::Error::new(err).context("Can't initialize Redis"));

    tracing::info!("ℹ️ | Initializing database and redis connections...");
    let (db, redis) = try_join!(db, redis)?;

    // Con varias réplicas arrancando a la vez, sqlx toma un advisory lock: migra una sola.
    sqlx::migrate!()
      .run(&db)
      .await
      .context("Can't run migrations")?;

    let redis_info = monitor::redis::spawn(redis.clone());

    Ok(Self {
      db,
      redis,
      redis_info,
    })
  }
}

fn secs(seconds: u64) -> Duration {
  Duration::from_secs(seconds)
}
