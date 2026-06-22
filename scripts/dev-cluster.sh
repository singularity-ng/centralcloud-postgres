#!/usr/bin/env bash
# Local CNPG cluster that mirrors the prod image and topology.
# Runs in k3d (k3s in docker), primary + replica, same image digest as prod.
# Idempotent — re-running is a no-op when the cluster already exists.
#
# Usage:
#   centralcloud-postgres-dev-cluster           # boot
#   centralcloud-postgres-dev-cluster --chaos   # boot + kill primary once ready
#   centralcloud-postgres-dev-cluster --stop    # tear down
#
# Env vars (all optional):
#   CLUSTER_NAME          k3d cluster name         (default: centralcloud-dev)
#   PG_PORT               rw port-forward          (default: 5432)
#   PG_RO_PORT            ro port-forward          (default: 5433)
#   CNPG_OPERATOR_VERSION CNPG release tag         (default: 1.24.0)
#   CNPG_IMAGE            full image:tag@sha256:…  (default: prod digest)
#
# Purpose: catch the silent-failure classes (read-replica staleness, primary
# failover, PITR) that single-instance dev never surfaces. Day-to-day dev
# stays on the plain-docker `centralcloud-ops-dev-db` for speed. This
# script is the opt-in for replication/failover work and the weekly CI
# chaos test.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-centralcloud-dev}"
PG_PORT="${PG_PORT:-5432}"
PG_RO_PORT="${PG_RO_PORT:-5433}"
CNPG_OPERATOR_VERSION="${CNPG_OPERATOR_VERSION:-1.24.0}"
CNPG_IMAGE="${CNPG_IMAGE:-registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext@sha256:9a380e9b3647f59a6b6d41697147aead388bed3051e7c9f58c18f117e05370eb}"
NAMESPACE="${NAMESPACE:-databases}"

chaos=0
action="${1:-up}"
case "$action" in
  --stop|stop|down)
    k3d cluster delete "$CLUSTER_NAME"
    exit 0
    ;;
  --chaos|chaos)
    chaos=1
    ;;
  up|"")
    chaos=0
    ;;
  --help|-h)
    sed -n '3,15p' "$0"
    exit 0
    ;;
  *)
    echo "usage: $0 [up|--chaos|--stop]" >&2
    exit 2
    ;;
esac

# 1. k3d cluster (skip if already running)
if ! k3d cluster list 2>/dev/null | awk '{print $1}' | grep -Fxq "$CLUSTER_NAME"; then
  k3d cluster create "$CLUSTER_NAME" \
    --agents 2 \
    --port "${PG_PORT}:5432@loadbalancer" \
    --port "${PG_RO_PORT}:5433@loadbalancer" \
    --k3s-arg '--disable=traefik@server:*'
fi

# Switch kubectl context to our cluster so subsequent commands don't need
# the cluster name.
kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null

# 2. CNPG operator (server-side apply is idempotent)
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_OPERATOR_VERSION}/manifests/cnpg-${CNPG_OPERATOR_VERSION}.yaml"

# 3. namespace + cluster CR
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ops-postgres
  namespace: ${NAMESPACE}
spec:
  instances: 2
  imageName: "${CNPG_IMAGE}"
  storage:
    size: 1Gi
  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "128MB"
  bootstrap:
    initdb:
      database: centralcloud_ops
      owner: centralcloud_ops
EOF

# 4. Wait for primary
kubectl wait --for=condition=Ready pod \
  -l cnpg.io/cluster=ops-postgres,role=primary \
  -n "$NAMESPACE" --timeout=180s

# 5. Create the test database the integration suite uses.
#    Runs psql through the primary pod directly so we don't depend on the
#    `kubectl-cnpg` plugin (not in nixpkgs; would add 50 MB to the dev shell).
kubectl exec -n "$NAMESPACE" \
  $(kubectl get pod -n "$NAMESPACE" -l cnpg.io/cluster=ops-postgres,role=primary \
    -o jsonpath='{.items[0].metadata.name}') \
  -c postgres -- psql -U postgres -d centralcloud_ops \
  -c "CREATE DATABASE centralcloud_ops_test;" 2>/dev/null || true

# 6. Port-forwards (background). Kill any previous ones first.
pkill -f "port-forward.*ops-postgres-rw.*${PG_PORT}" 2>/dev/null || true
pkill -f "port-forward.*ops-postgres-ro.*${PG_RO_PORT}" 2>/dev/null || true
nohup kubectl port-forward -n "$NAMESPACE" svc/ops-postgres-rw "$PG_PORT":5432 \
  >/tmp/cnpg-rw.log 2>&1 &
nohup kubectl port-forward -n "$NAMESPACE" svc/ops-postgres-ro "$PG_RO_PORT":5432 \
  >/tmp/cnpg-ro.log 2>&1 &
trap 'pkill -f "port-forward.*ops-postgres-" 2>/dev/null || true' EXIT

# 7. Optional chaos: kill the primary, wait for the operator to elect a new one
if [ "$chaos" = "1" ]; then
  echo "Chaos: deleting primary pod"
  kubectl delete pod -n "$NAMESPACE" \
    -l cnpg.io/cluster=ops-postgres,role=primary \
    --grace-period=0 --force
  kubectl wait --for=condition=Ready pod \
    -l cnpg.io/cluster=ops-postgres,role=primary \
    -n "$NAMESPACE" --timeout=60s
fi

cat <<EOF
ops-postgres-rw → localhost:${PG_PORT}
ops-postgres-ro → localhost:${PG_RO_PORT}
EOF
