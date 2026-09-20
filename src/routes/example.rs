//! Ruta de ejemplo: copiá este archivo como punto de partida y borralo cuando ya no sirva.
use axum::{Json, Router, extract::Path, routing::get};
use serde::Serialize;

use crate::error::AppError;

// Genérico en el estado porque este handler no usa `State`: así se prueba sin base de datos.
pub fn router<S: Clone + Send + Sync + 'static>() -> Router<S> {
  Router::new().route("/api/example/{name}", get(greet))
}

#[derive(Serialize)]
struct Greeting {
  greeting: String,
}

async fn greet(Path(name): Path<String>) -> Result<Json<Greeting>, AppError> {
  if name.len() > 32 {
    return Err(AppError::BadRequest("name too long (max 32)".into()));
  }
  Ok(Json(Greeting {
    greeting: format!("hola {name}"),
  }))
}

#[cfg(test)]
mod tests {
  use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
  };
  use tower::ServiceExt;

  use super::router;

  async fn call(uri: &str) -> (StatusCode, String) {
    let req = Request::get(uri).body(Body::empty()).unwrap();
    let res = router::<()>().oneshot(req).await.unwrap();
    let status = res.status();
    let body = to_bytes(res.into_body(), usize::MAX).await.unwrap();
    (status, String::from_utf8(body.to_vec()).unwrap())
  }

  #[tokio::test]
  async fn greets() {
    let (status, body) = call("/api/example/mundo").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, r#"{"greeting":"hola mundo"}"#);
  }

  #[tokio::test]
  async fn rejects_long_names() {
    let (status, _) = call(&format!("/api/example/{}", "a".repeat(33))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
  }
}
