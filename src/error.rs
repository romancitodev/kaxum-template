use axum::{
  http::StatusCode,
  response::{IntoResponse, Response},
};

/// Error de los handlers: devolvelo como `Result<_, AppError>` y usá `?` con lo que quieras.
#[derive(Debug)]
pub enum AppError {
  BadRequest(String),
  NotFound(String),
  Internal(anyhow::Error),
}

impl IntoResponse for AppError {
  fn into_response(self) -> Response {
    match self {
      Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg).into_response(),
      Self::NotFound(msg) => (StatusCode::NOT_FOUND, msg).into_response(),
      Self::Internal(err) => {
        tracing::error!("{err:#}");
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
      }
    }
  }
}

impl<E: Into<anyhow::Error>> From<E> for AppError {
  fn from(err: E) -> Self {
    Self::Internal(err.into())
  }
}
