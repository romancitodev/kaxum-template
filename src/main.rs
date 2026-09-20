mod app;
mod config;
mod error;
mod monitor;
mod routes;

use axum::Router;
use futures::FutureExt;
use tokio::signal;

use std::future::{Future, IntoFuture};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use tower_http::{cors::CorsLayer, trace};

use crate::{app::App, config::Config};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
  dotenvy::dotenv().ok();
  tracing_subscriber::fmt::init();

  tracing::debug!("ℹ️ | Starting server...");
  let config = Config::from_env()?;
  let app = App::new(&config)
    .await
    .expect("Error while initializing the app config");

  tracing::info!("✅ | App initialized successfully");
  tracing::info!("ℹ️ | Starting server...");

  let app = Router::new()
    .merge(routes::health::router())
    .merge(routes::example::router())
    .layer(trace::TraceLayer::new_for_http())
    .layer(CorsLayer::permissive())
    .with_state(app);
  setup(app, config.bind_addr)
    .await
    .expect("Failed to start server");

  Ok(())
}

fn setup(app: Router, address: SocketAddr) -> impl Future<Output = std::io::Result<()>> {
  TcpListener::bind(address)
    .map(|bind| bind.expect("Failed to bind to address"))
    .then(move |listener| {
      tracing::info!("ℹ️ | Server listening on {address}");
      axum::serve(listener, app)
        .with_graceful_shutdown(shutdown())
        .into_future()
    })
}

async fn shutdown() {
  let ctrl_c = async {
    signal::ctrl_c()
      .await
      .expect("Failed to install Ctrl+C handler");
  };

  #[cfg(unix)]
  let terminate = async {
    signal::unix::signal(signal::unix::SignalKind::terminate())
      .expect("Failed to install SIGTERM handler")
      .recv()
      .await;
  };

  #[cfg(not(unix))]
  let terminate = std::future::pending::<()>();

  tokio::select! {
      () = ctrl_c => {},
      () = terminate => {},
  }

  tracing::info!("shutdown signal received, draining connections");
}
