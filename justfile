set shell := ["nu", "-c"]
set dotenv-load := true
set dotenv-filename := ".env"

up:
  docker compose -f docker/compose.yaml up -d

down:
  docker compose -f docker/compose.yaml down -v

run:
  cargo pretty run

build-docker:
  docker build -t axum-api:dev .
