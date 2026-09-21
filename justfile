set shell := ["nu", "-c"]
set dotenv-load := true
set dotenv-filename := ".env"

# Única fuente del nombre: el `name` de Cargo.toml. Para otro proyecto alcanza con cambiarlo ahí.
project := `open Cargo.toml | get package.name`
cluster := project
ns      := "app"
image   := "api:dev"
k8s     := "kubernetes"
compose := "docker compose -p " + project + " --env-file .env -f docker/compose.yaml"
# 127.0.0.1 y no localhost: en Windows localhost puede resolver primero a IPv6 y demorar.
url     := "http://127.0.0.1:8080"

alias ship   := k8s-ship
alias logs   := k8s-logs
alias status := k8s-status

# Lista las recetas por grupo. Las destructivas piden confirmación (`just --yes <receta>` la omite).
[private]
default:
  @just --list --unsorted

# ─── local ──────────────────────────────────────────────────────────────────

# Verifica que estén instaladas las herramientas que usa este justfile
[group('local')]
doctor:
  ["docker" "kind" "kubectl" "cargo" "oha" "k9s" "curl"] | each {|t| {tool: $t, ok: (which $t | is-not-empty)} }

# Postgres, Redis, Drizzle Gateway y el diagrama ER en Docker
[group('local')]
up:
  {{compose}} up -d

# Pausa el compose sin borrar nada (se retoma con `just up`)
[group('local')]
stop:
  {{compose}} stop

# Baja el compose y borra sus volúmenes
[group('local'), confirm('Esto borra los volúmenes del compose (Postgres y Redis locales). ¿Seguir?')]
down:
  {{compose}} down -v

# Corre la API en local contra el compose
[group('local')]
run:
  cargo pretty run

# Corre los tests. Los que usan Postgres necesitan `just up`; corren en bases temporales, no tocan la tuya.
[group('local')]
test:
  with-env {DATABASE_URL: $"postgres://($env.POSTGRES_USER):($env.POSTGRES_PASSWORD)@localhost:5432/postgres"} { cargo test }

# Construye la imagen de la API
[group('local')]
build-docker:
  docker build -t {{image}} .

# ─── k8s ────────────────────────────────────────────────────────────────────

# Levanta todo desde cero (el clúster no debe existir)
[group('k8s')]
k8s-up: k8s-cluster k8s-namespace k8s-image k8s-metrics k8s-apply

# Crea el clúster de kind (1 control-plane + 3 workers)
[group('k8s')]
k8s-cluster:
  open --raw {{k8s}}/kind.config.yaml | str replace --all '__PROJECT__' '{{project}}' | kind create cluster --name {{cluster}} --config -

# Crea el namespace y lo deja como default del contexto actual
[group('k8s')]
k8s-namespace:
  kubectl apply -f {{k8s}}/base/namespace.yaml
  kubectl config set-context --current --namespace={{ns}}

# Construye la imagen y la carga en los nodos de kind
[group('k8s')]
k8s-image: build-docker
  kind load docker-image {{image}} --name {{cluster}}

# Instala metrics-server (lo necesita el HPA), con el ajuste para kind
[group('k8s')]
k8s-metrics:
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl patch deployment metrics-server -n kube-system --type=json --patch-file {{k8s}}/dev/metrics-server-patch.json
  kubectl rollout status deployment/metrics-server -n kube-system

# Crea (o actualiza) los secrets del clúster a partir de .env: no hay contraseñas en los manifiestos
[group('k8s')]
k8s-secrets: k8s-namespace
  kubectl create secret generic postgres-credentials -n {{ns}} $"--from-literal=POSTGRES_USER=($env.POSTGRES_USER)" $"--from-literal=POSTGRES_PASSWORD=($env.POSTGRES_PASSWORD)" $"--from-literal=POSTGRES_DB=($env.POSTGRES_DB)" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic api-secrets -n {{ns}} $"--from-literal=DATABASE_URL=postgres://($env.POSTGRES_USER):($env.POSTGRES_PASSWORD)@postgres:5432/($env.POSTGRES_DB)" --from-literal=REDIS_URL=redis://redis:6379 --dry-run=client -o yaml | kubectl apply -f -

# Aplica todo (base + dev) con Kustomize. Antes crea el namespace y los secrets (`k8s-secrets`), que van fuera de Kustomize.
[group('k8s')]
k8s-apply: k8s-secrets
  kubectl apply -k {{k8s}}/dev

# Muestra el YAML final que arma Kustomize, sin aplicar nada
[group('k8s')]
k8s-render:
  kubectl kustomize {{k8s}}/dev

# Valida contra el servidor lo que aplicaría, sin cambiar nada (el namespace tiene que existir)
[group('k8s')]
k8s-check:
  kubectl apply -k {{k8s}}/dev --dry-run=server

# Reconstruye la imagen, la carga y reinicia la API (ciclo de desarrollo)
[group('k8s')]
k8s-redeploy: k8s-image k8s-restart

# Reinicia la API sin reconstruir la imagen (por ejemplo, tras cambiar los secrets con `k8s-secrets`)
[group('k8s')]
k8s-restart:
  kubectl rollout restart deployment/api -n {{ns}}
  kubectl rollout status deployment/api -n {{ns}}

# Redeploy y prueba de salud en un solo paso
[group('k8s')]
k8s-ship: k8s-redeploy health

# Sube o baja réplicas de un Deployment: `just k8s-scale redis 0`
[group('k8s')]
k8s-scale name replicas:
  kubectl scale deployment/{{name}} -n {{ns}} --replicas={{replicas}}

# Pausa el clúster (apaga los nodos) sin borrar nada, para liberar RAM
[group('k8s')]
k8s-stop:
  kind get nodes --name {{cluster}} | lines | each {|n| docker stop $n }

# Retoma un clúster pausado, o tras reiniciar Docker o la PC, y espera a que los nodos estén Ready
[group('k8s')]
k8s-start:
  kind get nodes --name {{cluster}} | lines | sort-by {|n| not ($n | str contains "control-plane") } | each {|n| docker start $n }
  for _ in 1..60 { if ((^kubectl --context kind-{{cluster}} get --raw /readyz | complete).exit_code == 0) { break }; sleep 3sec }
  kubectl --context kind-{{cluster}} wait --for=condition=Ready node --all --timeout=180s

# Borra el namespace y deja el clúster (la data de Postgres se conserva)
[group('k8s'), confirm('Esto borra el namespace de la API con todo lo que tiene adentro. ¿Seguir?')]
k8s-clean:
  kubectl delete namespace {{ns}}

# Borra el clúster entero (la data de Postgres se conserva)
[group('k8s'), confirm('Esto borra el clúster de kind entero. ¿Seguir?')]
k8s-destroy:
  kind delete cluster --name {{cluster}}

# ⚠ Borra la data de Postgres del clúster. Es la única receta que la elimina.
[group('k8s'), confirm('Esto BORRA PARA SIEMPRE la data de Postgres del clúster. ¿Seguir?')]
k8s-wipe-data:
  kubectl delete deployment/postgres -n {{ns}} --ignore-not-found
  docker run --rm --entrypoint sh -v /var/lib/kind-{{project}}-pg:/d postgres:alpine3.24 -c 'rm -rf /d/*'

# ─── inspeccion ─────────────────────────────────────────────────────────────

# Vista general del namespace
[group('inspeccion')]
k8s-status:
  kubectl get pods,svc,hpa,pdb -n {{ns}}

# En qué nodo cayó cada pod (por defecto los de la API)
[group('inspeccion')]
k8s-nodes app="api":
  kubectl get pods -n {{ns}} -l app.kubernetes.io/name={{app}} -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName

# Logs en vivo de todos los pods de una app (por defecto la API): `just logs postgres`
[group('inspeccion')]
k8s-logs app="api":
  kubectl logs -n {{ns}} -l app.kubernetes.io/name={{app}} --tail=50 -f --prefix --max-log-requests=20

# Consumo de CPU y memoria por pod
[group('inspeccion')]
k8s-top:
  kubectl top pods -n {{ns}}

# Mira el HPA en vivo
[group('inspeccion')]
k8s-hpa:
  kubectl get hpa -n {{ns}} -w

# Interfaz de terminal para explorar el clúster
[group('inspeccion')]
k9:
  k9s -n {{ns}}

# ─── datos ──────────────────────────────────────────────────────────────────

# Crea una migración vacía en migrations/: `just db-new crear_usuarios`. La API las aplica al arrancar.
[group('datos')]
db-new name:
  "" | save $"migrations/(date now | format date '%Y%m%d%H%M%S')_{{name}}.sql"

# Levanta solo Drizzle Gateway (http://localhost:4983), sin Postgres ni Redis locales. Con `just k8s-pg` abierto ve el clúster.
[group('datos')]
db-ui:
  {{compose}} up -d --no-deps postgres-ui

# Regenera el diagrama ER desde migrations/ y lo sirve en http://localhost:8081
[group('datos')]
erd:
  {{compose}} up -d --build --force-recreate erd

# Carga sql/seed.sql en el Postgres local. Antes tiene que existir el esquema (lo crea la API al arrancar: `just run`). No se puede repetir.
[group('datos')]
db-seed:
  open --raw sql/seed.sql | {{compose}} exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# Vuelca la DB del compose local a .data/dump.sql
[group('datos')]
db-dump:
  mkdir .data
  {{compose}} exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" --clean --if-exists "$POSTGRES_DB"' | save -f .data/dump.sql

# Carga .data/dump.sql en el Postgres del clúster (reemplaza las tablas del dump)
[group('datos'), confirm('Esto reemplaza las tablas del Postgres del clúster con las del dump. ¿Seguir?')]
db-restore:
  open --raw .data/dump.sql | kubectl exec -i -n {{ns}} deploy/postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# ─── tuneles ────────────────────────────────────────────────────────────────

# Postgres del clúster en localhost:5433. El Gateway de Drizzle lo ve como la conexión `cluster`.
[group('tuneles')]
k8s-pg:
  kubectl port-forward -n {{ns}} svc/postgres 5433:5432

# Redis del clúster en localhost:6380
[group('tuneles')]
k8s-redis:
  kubectl port-forward -n {{ns}} svc/redis 6380:6379

# ─── pruebas ────────────────────────────────────────────────────────────────

# Pega a /health/ready por el NodePort
[group('pruebas')]
health:
  curl -si {{url}}/health/ready

# Carga suave: 300 req/s durante 1 minuto
[group('pruebas')]
load-soft:
  oha -z 1m -c 20 -q 300 {{url}}/health/live

# Carga fuerte: satura la CPU, el HPA escala hasta el máximo
[group('pruebas')]
load-hard:
  oha -z 3m -c 50 {{url}}/health/live
