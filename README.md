# bdd-sys

API en Rust (axum) con PostgreSQL y Redis, lista para correr en local con Docker o en un clúster de Kubernetes (kind).

Por ahora solo expone los endpoints de salud; sirve de base para construir el resto.

## Qué tiene

| Pieza | Qué hace |
|-------|----------|
| `src/main.rs` | Arranca el servidor, CORS abierto, trazas HTTP y apagado ordenado (Ctrl+C / SIGTERM). |
| `src/app.rs` | Estado compartido: pool de Postgres (`sqlx`) y conexión a Redis. |
| `src/routes/health.rs` | `GET /health/live`, `/health/ready` y `/health/startup`. |
| `src/monitor/redis.rs` | Heartbeat en background (PING cada 5 s) que guarda si Redis está arriba o caído. |
| `sql/seed.sql` | Datos de ejemplo. |
| `docker/` | `compose.yaml` (solo Drizzle Gateway, para ver la DB) y `full.compose.yaml` (Postgres + Redis + Drizzle Gateway). |
| `kubernetes/base/` | Manifiestos de la API: namespace, configmap, deployment, service, PDB y HPA. |
| `kubernetes/dev/` | Extras solo para desarrollo: Postgres, Redis, secret, NodePort y parche de metrics-server. |

### Health checks

- `live`: el proceso está vivo, no toca dependencias.
- `startup`: la app ya inicializó.
- `ready`: hace `SELECT 1` a Postgres (si falla, 503). Redis es opcional: si está caído responde 200 y lo marca como degradado.

### Variables de entorno (`.env`)

`DATABASE_URL`, `REDIS_URL`, `BIND_ADDR` y `RUST_LOG`.

## Justfile

Requiere [`just`](https://github.com/casey/just) y `nu` (nushell) como shell. Con `just` a secas se listan las recetas agrupadas (los grupos de abajo son los mismos que muestra la lista).

- Las recetas marcadas con ⚠ piden confirmación antes de correr. `just --yes <receta>` la omite.
- Alias: `ship` (`k8s-ship`), `logs` (`k8s-logs`) y `status` (`k8s-status`).
- Tienen parámetro opcional `app` (por defecto `api`): `k8s-logs` y `k8s-nodes`, ej. `just logs postgres`.

### `local`

| Receta | Qué hace |
|--------|----------|
| `doctor` | Verifica que estén instaladas las herramientas que usa el justfile. |
| `up` | Levanta el docker compose (Postgres, Redis y Drizzle Gateway). |
| `down` ⚠ | Baja el docker compose y borra sus volúmenes. |
| `run` | Corre la API en local con `cargo pretty run`. |
| `build-docker` | Construye la imagen `axum-api:dev`. |

### `k8s`

| Receta | Qué hace |
|--------|----------|
| `k8s-up` | Levanta todo desde cero en kind (el clúster no debe existir). |
| `k8s-cluster` | Crea el clúster kind (1 control-plane + 3 workers). |
| `k8s-namespace` | Crea el namespace `axum-api` y lo deja por defecto. |
| `k8s-image` | Construye la imagen y la carga en los nodos de kind. |
| `k8s-metrics` | Instala metrics-server (lo necesita el HPA). |
| `k8s-data` | Despliega Postgres, Redis y el secret de dev. |
| `k8s-api` | Despliega la API: configmap, deployment, service, PDB, HPA y NodePort. |
| `k8s-redeploy` | Reconstruye la imagen y reinicia la API (ciclo de desarrollo). |
| `k8s-ship` | `k8s-redeploy` + `health`: actualiza la API y la prueba. |
| `k8s-scale <name> <n>` | Cambia las réplicas de un Deployment, ej. `just k8s-scale redis 0`. |
| `k8s-clean` ⚠ | Borra el namespace, deja el clúster. La data de Postgres se conserva. |
| `k8s-destroy` ⚠ | Borra el clúster entero. La data de Postgres se conserva. |
| `k8s-wipe-data` ⚠ | Borra la data de Postgres. Es la única receta que lo hace. |

### `inspeccion`

| Receta | Qué hace |
|--------|----------|
| `k8s-status` | Vista general del namespace. |
| `k8s-nodes [app]` | En qué nodo está cada pod (por defecto los de la API). |
| `k8s-logs [app]` | Logs en vivo de todos los pods de una app (por defecto la API). |
| `k8s-top` | CPU y memoria por pod. |
| `k8s-hpa` | HPA en vivo. |
| `k9` | Abre k9s en el namespace. |

### `datos`

| Receta | Qué hace |
|--------|----------|
| `db-dump` | Vuelca el Postgres del compose local a `.data/dump.sql`. |
| `db-restore` ⚠ | Carga `.data/dump.sql` en el Postgres del clúster (reemplaza las tablas del dump). Se puede repetir. |

### `tuneles`

| Receta | Qué hace |
|--------|----------|
| `k8s-pg` | Postgres del clúster en `localhost:5433`. |
| `k8s-redis` | Redis del clúster en `localhost:6380`. |

### `pruebas`

| Receta | Qué hace |
|--------|----------|
| `health` | Pega a `/health/ready` por el NodePort (`127.0.0.1:8080`). |
| `load-soft` | Carga suave con `oha`: 300 req/s durante 1 minuto. |
| `load-hard` | Carga fuerte: satura la CPU y el HPA escala hasta el máximo. |

## Persistencia de Postgres en el clúster

La data vive en `/var/lib/kind-pg`, dentro de la VM de Docker, montada en el worker con la etiqueta `data=pg` (ver `kubernetes/kind.config.yaml`). Por eso sobrevive a `k8s-clean`, `k8s-destroy` y a recrear el clúster. Solo `just k8s-wipe-data` la borra.

No se usa una carpeta de Windows (`L:\...`) porque Postgres falla ahí con `Permission denied` en `pg_wal`.

Un clúster creado antes de este cambio no tiene el montaje ni la etiqueta: hay que hacer `just k8s-destroy` y `just k8s-up` una vez.

## Flujo de trabajo

Dos entornos: **local** (la API corre con `cargo` contra el compose) y **clúster** (la API corre en kind, como en producción).

### Primera vez

```
just up          # Postgres, Redis y Drizzle Gateway en Docker
just k8s-up      # clúster completo en kind
```

### Casos de uso

| Situación | Comando |
|-----------|---------|
| Estoy escribiendo la API | `just up` una vez, después `just run` (se reinicia a mano con Ctrl+C y `just run`). |
| Actualicé la API y quiero verla en el clúster | `just ship` (construye, carga, reinicia y prueba `/health/ready`). |
| Lo mismo pero sin la prueba | `just k8s-redeploy`. |
| Cambié un manifiesto de la API (deployment, HPA, configmap…) | `just k8s-api`. |
| Cambié Postgres, Redis o el secret | `just k8s-data`. |
| Quiero llevar mi data local al clúster | `just db-dump` y después `just db-restore`. |
| Quiero ver la DB del clúster con Drizzle Gateway | `just k8s-pg` y conectar a `localhost:5433`. |
| Algo falla en el clúster | `just status`, `just logs` (o `just logs postgres`), o `just k9`. |
| Probar que el HPA escala | `just k8s-hpa` en una terminal y `just load-hard` en otra. |
| Probar que Redis es opcional | `just k8s-scale redis 0` y `just health`: responde 200 con `degraded`. |
| Probar que Postgres es obligatorio | `just k8s-scale postgres 0` y `just health`: responde 503. |
| Terminé por hoy | `just down` y `just k8s-destroy` (piden confirmación). La data del clúster queda. |
| Quiero empezar con la DB del clúster vacía | `just k8s-wipe-data`, y después `just k8s-data`. |
