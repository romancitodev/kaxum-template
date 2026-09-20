set shell := ["nu", "-c"]
set dotenv-load := true
set dotenv-filename := ".env"

cluster := "axum"
ns      := "axum-api"
image   := "axum-api:dev"
k8s     := "kubernetes"
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

# Postgres, Redis y Drizzle Gateway en Docker
[group('local')]
up:
  docker compose -f docker/full.compose.yaml up -d

# Baja el compose y borra sus volúmenes
[group('local'), confirm('Esto borra los volúmenes del compose (Postgres y Redis locales). ¿Seguir?')]
down:
  docker compose -f docker/full.compose.yaml down -v

# Corre la API en local contra el compose
[group('local')]
run:
  cargo pretty run

# Construye la imagen de la API
[group('local')]
build-docker:
  docker build -t {{image}} .

# ─── k8s ────────────────────────────────────────────────────────────────────

# Levanta todo desde cero (el clúster no debe existir)
[group('k8s')]
k8s-up: k8s-cluster k8s-namespace k8s-image k8s-metrics k8s-data k8s-api

# Crea el clúster de kind (1 control-plane + 3 workers)
[group('k8s')]
k8s-cluster:
  kind create cluster --name {{cluster}} --config {{k8s}}/kind.config.yaml

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

# Postgres, Redis y credenciales de desarrollo
[group('k8s')]
k8s-data:
  kubectl apply -n {{ns}} -f {{k8s}}/dev/secret.yaml -f {{k8s}}/dev/postgres.yaml -f {{k8s}}/dev/redis.yaml

# La API: config, deployment, service, PDB, HPA y el NodePort de dev
[group('k8s')]
k8s-api:
  kubectl apply -n {{ns}} -f {{k8s}}/base/configmap.yaml -f {{k8s}}/base/deployment.yaml -f {{k8s}}/base/service.yaml -f {{k8s}}/base/pdb.yaml -f {{k8s}}/base/hpa.yaml -f {{k8s}}/dev/api-port.yaml

# Reconstruye la imagen, la carga y reinicia la API (ciclo de desarrollo)
[group('k8s')]
k8s-redeploy: k8s-image
  kubectl rollout restart deployment/api -n {{ns}}
  kubectl rollout status deployment/api -n {{ns}}

# Redeploy y prueba de salud en un solo paso
[group('k8s')]
k8s-ship: k8s-redeploy health

# Sube o baja réplicas de un Deployment: `just k8s-scale redis 0`
[group('k8s')]
k8s-scale name replicas:
  kubectl scale deployment/{{name}} -n {{ns}} --replicas={{replicas}}

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
  docker run --rm --entrypoint sh -v /var/lib/kind-pg:/d postgres:alpine3.24 -c 'rm -rf /d/*'

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

# Vuelca la DB del compose local a .data/dump.sql
[group('datos')]
db-dump:
  mkdir .data
  docker exec axum-postgres pg_dump -U postgres --clean --if-exists app | save -f .data/dump.sql

# Carga .data/dump.sql en el Postgres del clúster (reemplaza las tablas del dump)
[group('datos'), confirm('Esto reemplaza las tablas del Postgres del clúster con las del dump. ¿Seguir?')]
db-restore:
  open --raw .data/dump.sql | kubectl exec -i -n {{ns}} deploy/postgres -- psql -U postgres -d app

# ─── tuneles ────────────────────────────────────────────────────────────────

# Postgres del clúster en localhost:5433 (para el gateway de Drizzle)
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
