use std::time::Instant;

use axum::{
  Router,
  extract::{MatchedPath, Request, State},
  http::header,
  middleware::Next,
  response::{IntoResponse, Response},
  routing::get,
};

use metrics::{
  Unit, counter, describe_counter, describe_gauge, describe_histogram, gauge, histogram,
};
use metrics_exporter_prometheus::{Matcher, PrometheusBuilder, PrometheusHandle};
use sqlx::PgPool;

const LATENCY_BUCKETS: &[f64] = &[
  0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0,
];

pub fn install() -> anyhow::Result<PrometheusHandle> {
  let handle = PrometheusBuilder::new()
    .set_buckets_for_metric(
      Matcher::Full("http_request_duration_seconds".to_owned()),
      LATENCY_BUCKETS,
    )?
    .install_recorder()?;

  describe_counter!("http_requests_total", "Requests HTTP Atendidos");
  describe_histogram!(
    "http_request_duration_seconds",
    Unit::Seconds,
    "Latencia de los requests HTTP"
  );

  describe_gauge!("http_requests_in_flight", "Requests HTTP En curso");
  describe_gauge!(
    "db_pool_connections",
    "Conexiones en el pool de la base de datos"
  );
  describe_gauge!(
    "db_pool_max_connections",
    "Conexiones maximas en el pool de la base de datos"
  );
  describe_gauge!("redis_up", "Estado de la conexion a redis");

  describe_counter!(
    "redis_heartbeat_failures_total",
    "Numero de fallos en el heartbeat de redis"
  );
  describe_counter!(
    "cache_lookups_total",
    "Resultados de la busqueda en la cache de Redis (hit/miss)"
  );
  Ok(handle)
}

pub async fn track(req: Request, next: Next) -> Response {
  let method = req.method().to_string();
  let route = req
    .extensions()
    .get::<MatchedPath>()
    .map_or_else(|| "unmatched".to_owned(), |p| p.as_str().to_owned());

  let _in_flight = InFlight::new();
  let start = Instant::now();
  let res = next.run(req).await;

  let labels = [
    ("method", method),
    ("route", route),
    ("status", res.status().as_u16().to_string()),
  ];

  counter!("http_requests_total", &labels).increment(1);
  histogram!("http_request_duration_seconds", &labels).record(start.elapsed().as_secs_f64());
  res
}

struct InFlight;

impl InFlight {
  fn new() -> Self {
    gauge!("http_requests_in_flight").increment(1.0);
    Self
  }
}

impl Drop for InFlight {
  fn drop(&mut self) {
    gauge!("http_requests_in_flight").decrement(1.0);
  }
}

#[derive(Clone)]
struct Metrics {
  handle: PrometheusHandle,
  db: PgPool,
}

pub fn router(handle: PrometheusHandle, db: PgPool) -> Router {
  Router::new()
    .route("/metrics", get(scrape))
    .with_state(Metrics { handle, db })
}

async fn scrape(State(s): State<Metrics>) -> impl IntoResponse {
  let size = s.db.size();
  let idle = u32::try_from(s.db.num_idle()).unwrap_or(u32::MAX);

  gauge!("db_pool_connections", "state" => "idle").set(f64::from(idle));
  gauge!("db_pool_connections", "state" => "in_use").set(f64::from(size.saturating_sub(idle)));
  gauge!("db_pool_max_connections").set(f64::from(s.db.options().get_max_connections()));

  s.handle.run_upkeep();
  (
    [(
      header::CONTENT_TYPE,
      "text/plain; version=0.0.4; charset=utf-8",
    )],
    s.handle.render(),
  )
}
