//! Rate limit por IP y por ruta, con estado en Redis (así todos los pods
//! comparten el mismo contador — un limiter en memoria sería por pod, y el
//! límite real terminaría siendo `limite × réplicas`).
//!
//! Sliding window counter (el algoritmo de Cloudflare): en vez de un contador
//! que resetea de golpe cada minuto (deja pasar hasta 2x el límite si el
//! tráfico pega justo en el borde de dos ventanas), pondera el conteo de la
//! ventana anterior según cuánto de ella "todavía pesa" en la actual. Todo el
//! cálculo corre en un script Lua, así el GET+INCR+EXPIRE es atómico: sin esa
//! atomicidad, dos pedidos concurrentes podrían leer el mismo conteo viejo y
//! los dos creerse con lugar.
//!
//! La clave es `ratelimit:{ruta}:{ip}:{ventana}` — cada IP tiene su propio
//! balde por ruta. Si fuera sólo `{ruta}:{ventana}` (sin IP), el pedido de un
//! cliente nuevo se comería el 429 de otro que ya gastó el límite: eso es un
//! rate limit por *servicio*, no por *usuario*.
use std::{
  net::SocketAddr,
  sync::OnceLock,
  time::{SystemTime, UNIX_EPOCH},
};

use axum::{
  extract::{ConnectInfo, MatchedPath, Request, State},
  http::{StatusCode, header},
  middleware::Next,
  response::{IntoResponse, Response},
};
use redis::{Script, aio::ConnectionManager};

const WINDOW_MS: i64 = 60_000; // ventana de 1 minuto

/// Límite por IP y por minuto. Ajustar acá cuando se agreguen rutas nuevas.
fn max_requests_for(route: &str) -> i64 {
  match route {
    r if r.starts_with("/health") => 1000, // barato, y kubelet pega con su propia IP
    "/api/animales/{id}" => 500,
    _ => 200,
  }
}

const LUA: &str = r"
local curr = tonumber(redis.call('GET', KEYS[1]) or '0')
local prev = tonumber(redis.call('GET', KEYS[2]) or '0')

local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])

local elapsed = now % window
local weight = (window - elapsed) / window
local estimated = prev * weight + curr

if estimated >= limit then
  return 0
end

redis.call('INCR', KEYS[1])
redis.call('PEXPIRE', KEYS[1], window * 2)
return 1
";

fn script() -> &'static Script {
  static SCRIPT: OnceLock<Script> = OnceLock::new();
  SCRIPT.get_or_init(|| Script::new(LUA))
}

/// Si Redis falla, deja pasar el pedido: es una protección contra abuso.
pub async fn limit(
  State(mut redis): State<ConnectionManager>,
  ConnectInfo(addr): ConnectInfo<SocketAddr>,
  req: Request,
  next: Next,
) -> Response {
  let route = req
    .extensions()
    .get::<MatchedPath>()
    .map_or("unmatched", |p| p.as_str());
  let ip = addr.ip();
  let max_requests = max_requests_for(route);

  let now_ms = SystemTime::now()
    .duration_since(UNIX_EPOCH)
    .expect("el reloj del sistema está antes de 1970")
    .as_millis() as i64;
  let bucket = now_ms / WINDOW_MS;
  let curr_key = format!("ratelimit:{route}:{ip}:{bucket}");
  let prev_key = format!("ratelimit:{route}:{ip}:{}", bucket - 1);

  let allowed = script()
    .key(curr_key)
    .key(prev_key)
    .arg(now_ms)
    .arg(WINDOW_MS)
    .arg(max_requests)
    .invoke_async::<i64>(&mut redis)
    .await;

  match allowed {
    Ok(0) => {
      tracing::warn!("rate limit alcanzado en {route}");
      (
        StatusCode::TOO_MANY_REQUESTS,
        [(header::RETRY_AFTER, "1")],
        "demasiados pedidos, esperá un toque",
      )
        .into_response()
    }
    Ok(_) => next.run(req).await,
    Err(err) => {
      tracing::warn!("rate limiter sin Redis, dejo pasar el pedido: {err}");
      next.run(req).await
    }
  }
}

#[cfg(test)]
mod tests {
  use redis::{AsyncCommands, Client};

  use super::*;

  async fn redis_conn() -> ConnectionManager {
    dotenvy::dotenv().ok();
    let url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".into());
    ConnectionManager::new(Client::open(url).unwrap())
      .await
      .unwrap()
  }

  async fn clear(redis: &mut ConnectionManager, key_prefix: &str) {
    let now_ms = SystemTime::now()
      .duration_since(UNIX_EPOCH)
      .unwrap()
      .as_millis() as i64;
    let bucket = now_ms / WINDOW_MS;
    let _: () = redis
      .del(format!("{key_prefix}:{bucket}"))
      .await
      .unwrap_or(());
    let _: () = redis
      .del(format!("{key_prefix}:{}", bucket - 1))
      .await
      .unwrap_or(());
  }

  /// Corre el script `n` veces contra un prefijo de clave dado y devuelve el
  /// resultado de la última llamada (1 = permitido, 0 = bloqueado).
  async fn hit(redis: &mut ConnectionManager, key_prefix: &str, max_requests: i64, n: i64) -> i64 {
    let now_ms = SystemTime::now()
      .duration_since(UNIX_EPOCH)
      .unwrap()
      .as_millis() as i64;
    let bucket = now_ms / WINDOW_MS;
    let curr_key = format!("{key_prefix}:{bucket}");
    let prev_key = format!("{key_prefix}:{}", bucket - 1);

    let mut last = 1;
    for _ in 0..n {
      last = script()
        .key(curr_key.clone())
        .key(prev_key.clone())
        .arg(now_ms)
        .arg(WINDOW_MS)
        .arg(max_requests)
        .invoke_async::<i64>(redis)
        .await
        .unwrap();
    }
    last
  }

  #[tokio::test]
  async fn blocks_after_the_limit() {
    let mut redis = redis_conn().await;
    let key = "ratelimit:test:blocks_after_the_limit:127.0.0.1";
    clear(&mut redis, key).await;

    assert_eq!(hit(&mut redis, key, 5, 5).await, 1, "el 5to pedido entra");
    assert_eq!(
      hit(&mut redis, key, 5, 1).await,
      0,
      "el 6to pedido se bloquea"
    );

    clear(&mut redis, key).await;
  }

  /// Responde exactamente a la pregunta de "esto es per-usuario o per-servicio":
  /// si la IP no estuviera en la clave, agotar el límite para una IP también
  /// bloquearía a la otra. Acá comparten ruta y ventana, sólo cambia la IP, y
  /// la segunda sigue teniendo su balde entero disponible.
  #[tokio::test]
  async fn different_ips_get_independent_budgets() {
    let mut redis = redis_conn().await;
    let key_a = "ratelimit:test:independent_budgets:203.0.113.1"; // "cliente" ya agotado
    let key_b = "ratelimit:test:independent_budgets:203.0.113.2"; // pedido nuevo, primera vez
    clear(&mut redis, key_a).await;
    clear(&mut redis, key_b).await;

    assert_eq!(
      hit(&mut redis, key_a, 5, 5).await,
      1,
      "la IP A gasta su límite"
    );
    assert_eq!(
      hit(&mut redis, key_a, 5, 1).await,
      0,
      "la IP A ya está bloqueada"
    );
    assert_eq!(
      hit(&mut redis, key_b, 5, 1).await,
      1,
      "la IP B nunca pidió nada, no debería ver un 429"
    );

    clear(&mut redis, key_a).await;
    clear(&mut redis, key_b).await;
  }
}
