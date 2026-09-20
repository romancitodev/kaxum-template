# syntax=docker/dockerfile:1

FROM rust:1-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock build.rs ./
COPY migrations ./migrations
COPY src ./src
# `cargo install` deja el binario con el nombre del paquete, así no hay que repetirlo acá.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/app/target \
    cargo install --path . --locked --root /out --target-dir /app/target && cp /out/bin/* /server

FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /server /server
EXPOSE 3000
ENTRYPOINT ["/server"]
