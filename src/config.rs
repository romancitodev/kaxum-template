use std::net::SocketAddr;

use anyhow::Context;

pub struct Config {
  pub bind_addr: SocketAddr,
  pub database_url: String,
  pub redis_url: String,
  #[cfg(feature = "metrics")]
  pub metrics_addr: SocketAddr,
}

impl Config {
  pub fn from_env() -> anyhow::Result<Self> {
    let bind_addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:3000".into());

    #[cfg(feature = "metrics")]
    let metrics_addr = std::env::var("METRICS_ADDR").unwrap_or_else(|_| "127.0.0.1:9090".into());

    Ok(Self {
      bind_addr: bind_addr
        .parse()
        .with_context(|| format!("BIND_ADDR inválida: {bind_addr}"))?,
      database_url: required("DATABASE_URL")?,
      redis_url: required("REDIS_URL")?,
      #[cfg(feature = "metrics")]
      metrics_addr: metrics_addr
        .parse()
        .with_context(|| format!("METRICS_ADDR inválida: {metrics_addr}"))?,
    })
  }
}

fn required(name: &str) -> anyhow::Result<String> {
  std::env::var(name).with_context(|| format!("{name} must be set"))
}
