mod app;
mod config;
mod error;
mod monitor;
mod routes;

use axum::Router;
#[cfg(feature = "metrics")]
use axum::middleware;
use futures::FutureExt;
use tokio::signal;

use std::future::{Future, IntoFuture};
use std::net::SocketAddr;
use tokio::net::TcpListener;
use tower_http::{cors::CorsLayer, trace};

#[cfg(feature = "metrics")]
use crate::routes::metrics;
use crate::{app::App, config::Config};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
  dotenvy::dotenv().ok();
  tracing_subscriber::fmt::init();

  #[cfg(feature = "metrics")]
  let metrics = metrics::install()?;

  tracing::debug!("ℹ️ | Starting server...");
  let config = Config::from_env()?;
  let app = App::new(&config).await?;

  #[cfg(feature = "metrics")]
  let metrics_app = metrics::router(metrics, app.db.clone());

  tracing::info!("✅ | App initialized successfully");
  tracing::info!("ℹ️ | Starting server...");

  let router = Router::new()
    .merge(routes::health::router())
    .merge(routes::example::router());

  #[cfg(feature = "metrics")]
  let router = router.layer(middleware::from_fn(metrics::track));

  let app = router
    .layer(trace::TraceLayer::new_for_http())
    .layer(CorsLayer::permissive())
    .with_state(app);

  let app_handle = setup(app, config.bind_addr);

  #[cfg(feature = "metrics")]
  let metrics_handle = setup(metrics_app, config.metrics_addr);

  #[cfg(feature = "metrics")]
  futures::try_join!(app_handle, metrics_handle)?;

  #[cfg(not(feature = "metrics"))]
  app_handle.await?;

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
