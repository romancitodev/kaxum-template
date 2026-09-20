# syntax=docker/dockerfile:1

FROM rust:1-bookworm AS builder
# Tiene que coincidir con el `name` de [package] en Cargo.toml
ARG BIN=bdd-sys
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    cargo build --release --locked && cp target/release/${BIN} /server

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 3000
ENTRYPOINT ["/server"]
