//! `GET /api/animales/{id}`: usa Postgres y Redis juntos (cache-aside).
use std::time::Duration;

use axum::{
  Json, Router,
  extract::{Path, State},
  routing::get,
};
use redis::{AsyncCommands, aio::ConnectionManager};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::{app::App, error::AppError};

const CACHE_TTL: Duration = Duration::from_secs(60);

pub fn router() -> Router<App> {
  Router::new().route("/api/animales/{id}", get(get_animal))
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
struct AnimalDetail {
  id_animal: i32,
  nombre: String,
  fecha_nacimiento: Option<String>,
  especie: String,
  recinto: String,
}

/// Primero busca en Redis (caché); si no está, consulta Postgres y guarda el
/// resultado en Redis para la próxima. Si Redis falla, sigue a Postgres sin
/// cortar el pedido.
async fn get_animal(
  State(db): State<PgPool>,
  State(mut redis): State<ConnectionManager>,
  Path(id): Path<i32>,
) -> Result<Json<AnimalDetail>, AppError> {
  let cache_key = format!("animal:{id}");

  if let Ok(Some(cached)) = redis.get::<_, Option<String>>(&cache_key).await
    && let Ok(animal) = serde_json::from_str(&cached)
  {
    #[cfg(feature = "metrics")]
    metrics::counter!("cache_lookups_total", "result" => "hit").increment(1);
    return Ok(Json(animal));
  }

  #[cfg(feature = "metrics")]
  metrics::counter!("cache_lookups_total", "result" => "miss").increment(1);

  let animal = sqlx::query_as::<_, AnimalDetail>(
    r"
    SELECT a.id_animal, a.nombre, a.fecha_nacimiento::TEXT AS fecha_nacimiento,
           e.nombre_comun AS especie, r.nombre AS recinto
    FROM animal a
    JOIN especie e ON e.id_especie = a.id_especie
    JOIN recinto r ON r.id_recinto = a.id_recinto
    WHERE a.id_animal = $1
    ",
  )
  .bind(id)
  .fetch_optional(&db)
  .await?
  .ok_or_else(|| AppError::NotFound(format!("animal {id} no existe")))?;

  if let Ok(payload) = serde_json::to_string(&animal) {
    let _: Result<(), _> = redis.set_ex(&cache_key, payload, CACHE_TTL.as_secs()).await;
  }

  Ok(Json(animal))
}

#[cfg(test)]
mod tests {
  use redis::Client;

  use super::*;

  async fn redis_conn() -> ConnectionManager {
    dotenvy::dotenv().ok();
    let url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".into());
    ConnectionManager::new(Client::open(url).unwrap())
      .await
      .unwrap()
  }

  #[sqlx::test]
  async fn cache_aside_serves_stale_reads_from_redis(pool: PgPool) {
    sqlx::query(
      "INSERT INTO recinto (id_recinto, nombre, tipo, capacidad) VALUES (1, 'Test', 'terrestre', 1)",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO especie (id_especie, nombre_comun) VALUES (1, 'Test especie')")
      .execute(&pool)
      .await
      .unwrap();
    sqlx::query(
      "INSERT INTO animal (id_animal, nombre, id_especie, id_recinto) VALUES (1, 'Test animal', 1, 1)",
    )
    .execute(&pool)
    .await
    .unwrap();

    let mut redis = redis_conn().await;
    let _: () = redis.del("animal:1").await.unwrap_or(());

    let first = get_animal(State(pool.clone()), State(redis.clone()), Path(1))
      .await
      .unwrap()
      .0;
    assert_eq!(first.nombre, "Test animal");

    // Ya no está en Postgres: si esto sigue funcionando, la respuesta vino de la caché.
    sqlx::query("DELETE FROM animal WHERE id_animal = 1")
      .execute(&pool)
      .await
      .unwrap();

    let cached = get_animal(State(pool), State(redis.clone()), Path(1))
      .await
      .unwrap()
      .0;
    assert_eq!(cached.nombre, "Test animal");

    let _: () = redis.del("animal:1").await.unwrap_or(());
  }

  #[sqlx::test]
  async fn returns_404_when_animal_does_not_exist(pool: PgPool) {
    let mut redis = redis_conn().await;
    let _: () = redis.del("animal:999999").await.unwrap_or(());

    let err = get_animal(State(pool), State(redis), Path(999_999))
      .await
      .unwrap_err();
    assert!(matches!(err, AppError::NotFound(_)));
  }
}
