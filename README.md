# bdd-sys

API en Rust (axum) con PostgreSQL y Redis, lista para correr en local con Docker o en un clúster de Kubernetes (kind).

Por ahora solo expone los endpoints de salud; sirve de base para construir el resto.

## Qué tiene

| Pieza | Qué hace |
|-------|----------|
| `src/main.rs` | Arranca el servidor, CORS abierto, trazas HTTP y apagado ordenado (Ctrl+C / SIGTERM). |
| `src/config.rs` | Lee las variables de entorno en un solo lugar (`Config::from_env`). |
| `src/error.rs` | `AppError`: los handlers devuelven `Result<_, AppError>` y pueden usar `?` con cualquier error (500 con log) o `AppError::BadRequest` (400). |
| `src/app.rs` | Estado compartido: pool de Postgres (`sqlx`), conexión a Redis y migraciones al arrancar. |
| `src/routes/health.rs` | `GET /health/live`, `/health/ready` y `/health/startup`. |
| `src/routes/example.rs` | Ruta de ejemplo `GET /api/example/{name}` con sus tests. Copiarla como punto de partida y borrarla. |
| `src/monitor/redis.rs` | Heartbeat en background (PING cada 5 s) que guarda si Redis está arriba o caído. |
| `migrations/` | El esquema: migraciones de sqlx (`<timestamp>_<nombre>.sql`), hoy el del zoológico. La API las aplica al arrancar; `build.rs` hace que cargo las detecte. Sin `BEGIN`/`COMMIT`: sqlx ya abre la transacción. |
| `sql/seed.sql` | Datos de ejemplo del zoológico. Se cargan con `just db-seed` una vez creado el esquema. Borrar en un proyecto nuevo. |
| `docker/` | `compose.yaml` (Postgres, Redis, Drizzle Gateway y el diagrama ER) y `erd/` (imagen de Liam ERD). |
| `kubernetes/base/` | Manifiestos de la API: namespace, configmap, deployment, service, PDB y HPA. |
| `kubernetes/dev/` | Extras solo para desarrollo: Postgres, Redis, secret, NodePort y parche de metrics-server. |

### Health checks

- `live`: el proceso está vivo, no toca dependencias.
- `startup`: la app ya inicializó.
- `ready`: hace `SELECT 1` a Postgres (si falla, 503). Redis es opcional: si está caído responde 200 y lo marca como degradado.

### Variables de entorno (`.env`)

`cp .env.example .env` y cambiar las contraseñas. Es la única fuente de credenciales: las lee el justfile, el compose (`--env-file`) y la API, y `just k8s-secrets` arma con ellas los secrets del clúster.

- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` y `MASTERPASS` (Drizzle Gateway): obligatorias. Sin ellas `just up` falla con un mensaje.
- `DATABASE_URL` y `REDIS_URL`: obligatorias para correr la API en local.
- `BIND_ADDR` (por defecto `0.0.0.0:3000`) y `RUST_LOG`: opcionales.

Postgres toma la contraseña solo al crear su data. Si la cambiás después, no se aplica sola: hay que borrar la data (`just down` en local, `just k8s-wipe-data` en el clúster) o cambiarla con `ALTER USER`.

## Justfile

Requiere [`just`](https://github.com/casey/just) y `nu` (nushell) como shell. El nombre del proyecto (clúster de kind, proyecto de compose y carpeta de data) sale del `name` de `Cargo.toml`. Con `just` a secas se listan las recetas agrupadas (los grupos de abajo son los mismos que muestra la lista).

- Las recetas marcadas con ⚠ piden confirmación antes de correr. `just --yes <receta>` la omite.
- Alias: `ship` (`k8s-ship`), `logs` (`k8s-logs`) y `status` (`k8s-status`).
- Tienen parámetro opcional `app` (por defecto `api`): `k8s-logs` y `k8s-nodes`, ej. `just logs postgres`.

### `local`

| Receta | Qué hace |
|--------|----------|
| `doctor` | Verifica que estén instaladas las herramientas que usa el justfile. |
| `up` | Levanta el docker compose (Postgres, Redis, Drizzle Gateway y el diagrama ER). |
| `stop` | Pausa el docker compose sin borrar nada (se retoma con `up`). |
| `down` ⚠ | Baja el docker compose y borra sus volúmenes. |
| `run` | Corre la API en local con `cargo pretty run`. |
| `test` | Corre los tests. Los que usan Postgres necesitan `just up` y corren en bases temporales: no tocan tu base. |
| `build-docker` | Construye la imagen `api:dev`. |

### `k8s`

| Receta | Qué hace |
|--------|----------|
| `k8s-up` | Levanta todo desde cero en kind (el clúster no debe existir). |
| `k8s-cluster` | Crea el clúster kind (1 control-plane + 3 workers). |
| `k8s-namespace` | Crea el namespace `app` y lo deja por defecto. |
| `k8s-image` | Construye la imagen y la carga en los nodos de kind. |
| `k8s-metrics` | Instala metrics-server (lo necesita el HPA). |
| `k8s-secrets` | Crea o actualiza los secrets del clúster desde `.env` (contraseñas de Postgres y `DATABASE_URL` de la API). |
| `k8s-data` | Despliega Postgres y Redis (corre `k8s-secrets` antes). |
| `k8s-api` | Despliega la API: configmap, deployment, service, PDB, HPA y NodePort. |
| `k8s-redeploy` | Reconstruye la imagen y reinicia la API (ciclo de desarrollo). |
| `k8s-ship` | `k8s-redeploy` + `health`: actualiza la API y la prueba. |
| `k8s-stop` | Pausa el clúster (apaga los nodos) sin borrar nada, para liberar RAM. |
| `k8s-start` | Retoma un clúster pausado, o tras reiniciar Docker o la PC, y espera a que los nodos estén Ready. |
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
| `db-new <nombre>` | Crea una migración vacía en `migrations/`, ej. `just db-new crear_usuarios`. La API la aplica al arrancar. |
| `db-ui` | Levanta solo Drizzle Gateway, sin Postgres ni Redis locales. Con `just k8s-pg` abierto ve el clúster. |
| `erd` | Regenera el diagrama ER desde `migrations/` y lo sirve en `http://localhost:8081`. |
| `db-seed` | Carga `sql/seed.sql` en el Postgres local. Antes tiene que existir el esquema (`just run`). No se puede repetir. |
| `db-dump` | Vuelca el Postgres del compose local a `.data/dump.sql`. |
| `db-restore` ⚠ | Carga `.data/dump.sql` en el Postgres del clúster (reemplaza las tablas del dump). Se puede repetir. |

### `tuneles`

| Receta | Qué hace |
|--------|----------|
| `k8s-pg` | Postgres del clúster en `localhost:5433`. El Gateway de Drizzle lo ve como la conexión `cluster`. |
| `k8s-redis` | Redis del clúster en `localhost:6380`. |

### `pruebas`

| Receta | Qué hace |
|--------|----------|
| `health` | Pega a `/health/ready` por el NodePort (`127.0.0.1:8080`). |
| `load-soft` | Carga suave con `oha`: 300 req/s durante 1 minuto. |
| `load-hard` | Carga fuerte: satura la CPU y el HPA escala hasta el máximo. |

## Persistencia de Postgres en el clúster

La data vive en `/var/lib/kind-<proyecto>-pg`, dentro de la VM de Docker, montada en el worker con la etiqueta `data=pg` (ver `kubernetes/kind.config.yaml`). Por eso sobrevive a `k8s-clean`, `k8s-destroy` y a recrear el clúster. Solo `just k8s-wipe-data` la borra.

No se usa una carpeta de Windows (`L:\...`) porque Postgres falla ahí con `Permission denied` en `pg_wal`.

Un clúster creado antes de este cambio no tiene el montaje, la etiqueta ni los nombres nuevos: hay que borrarlo (`kind delete cluster --name axum`) y hacer `just k8s-up` una vez.

## Flujo de trabajo

Dos entornos: **local** (la API corre con `cargo` contra el compose) y **clúster** (la API corre en kind, como en producción).

### Primera vez

```
cp .env.example .env
just doctor      # ¿están instaladas las herramientas?
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
| Necesito una tabla o un cambio de esquema | `just db-new <nombre>`, escribir el SQL en el archivo creado y reiniciar la API (`just run` o `just ship`). |
| Quiero llevar mi data local al clúster | `just db-dump` y después `just db-restore`. |
| Quiero ver la DB del clúster con Drizzle Gateway | `just k8s-pg` y conectar a `localhost:5433`. |
| Algo falla en el clúster | `just status`, `just logs` (o `just logs postgres`), o `just k9`. |
| Probar que el HPA escala | `just k8s-hpa` en una terminal y `just load-hard` en otra. |
| Probar que Redis es opcional | `just k8s-scale redis 0` y `just health`: responde 200 con `degraded`. |
| Probar que Postgres es obligatorio | `just k8s-scale postgres 0` y `just health`: responde 503. |
| Terminé por hoy | `just stop` y `just k8s-stop`: pausan todo sin borrar nada. |
| Al día siguiente | `just up` y `just k8s-start` (también sirve tras reiniciar Docker o la PC). |
| Quiero borrar todo | `just down` (borra los datos locales del compose) y `just k8s-destroy` (la data del clúster queda). |
| Quiero empezar con la DB del clúster vacía | `just k8s-wipe-data`, y después `just k8s-data`. |

## Usar como template

1. Cambiar el `name` en `Cargo.toml` y correr `cargo check` (actualiza `Cargo.lock`). El justfile, el clúster, el compose y la carpeta de data siguen ese nombre solos.
2. Borrar `sql/seed.sql` y la migración `..._esquema_inicial.sql`, y escribir el esquema propio con `just db-new`. El diagrama ER necesita al menos una migración.
3. Cambiar las contraseñas en `.env` y borrar `src/routes/example.rs` cuando ya tengas rutas propias.

El puerto `8080` del host (en `kubernetes/kind.config.yaml` y `url` del justfile) es fijo: dos clústeres de proyectos distintos no pueden estar arriba a la vez.

## Drizzle Gateway (`http://localhost:4983`)

Muestra dos conexiones: `local` (el Postgres del compose) y `cluster` (el del clúster). Para ver la del clúster hay que tener abierto `just k8s-pg`; sin el túnel esa conexión no responde. El puerto 5433 del túnel es distinto del 5432 del compose para que puedan estar los dos a la vez.

El Gateway toma las conexiones de las variables `DATABASE_URL_*` solo cuando crea su volumen. Si ya tenías el volumen de antes, `cluster` no aparece: agregala una vez desde la interfaz del Gateway (`postgresql://<usuario>:<contraseña>@host.docker.internal:5433/<base>`) o recreá el volumen (solo guarda la configuración del Gateway, no datos de Postgres):

```
docker compose -p <proyecto> -f docker/compose.yaml rm -sf postgres-ui
docker volume rm <proyecto>_drizzle-data
just up
```

Para mirar solo la data del clúster, sin levantar el Postgres ni el Redis locales: `just db-ui` en una terminal y `just k8s-pg` en otra.

## Diagrama ER (`http://localhost:8081`)

Lo genera [Liam ERD](https://liambx.com) desde `migrations/` (junta todas en orden) y lo sirve el servicio `erd` del compose (arranca con `just up`). Después de agregar o cambiar una migración, `just erd` lo regenera.

## Datos de ejemplo (zoológico)

El esquema lo crea la API al arrancar (es la migración de `migrations/`) y los datos no se cargan solos: hay que cargar el seed aparte.

```
just up
just run        # crea el esquema; Ctrl+C cuando termine de iniciar
just db-seed    # carga sql/seed.sql
```

El seed no se puede cargar dos veces (da `duplicate key` y no deja nada a medias). Para empezar de nuevo: `just down`, `just up`, `just run` y `just db-seed`.

## Tests con Postgres

`#[sqlx::test]` crea una base temporal por test, le aplica `migrations/` y la borra al terminar (ejemplo en `src/routes/health.rs`). `just test` apunta a la base `postgres` del compose para no dejar nada en la tuya.
