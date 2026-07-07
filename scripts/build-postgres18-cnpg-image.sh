#!/usr/bin/env bash
# Build the CentralCloud PostgreSQL 18 CNPG image via nix2container.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation only (no publish)
#   PUSH=1            — nix2container copyToRegistry → internal registry
#   PUSH=both         — internal registry, then GHCR mirror (second copyToRegistry)
#   USE_REMOTE_BUILDERS=1 — allow nix to dispatch to remote builders.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_image="${PUSH:-0}"
use_remote_builders="${USE_REMOTE_BUILDERS:-0}"
nix_build_args=()

INTERNAL_TAG="registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext"
GHCR_TAG="ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext"

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

# copyToRegistry shells out to skopeo; the login step must use the same
# authfile and nix run must be impure so the sandboxed skopeo can read it.
if [[ "$push_image" != "0" ]]; then
  nix_build_args+=(--impure --accept-flake-config)
fi

case "$push_image" in
  0)
    nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --no-link
    ;;
  1)
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry"
    ;;
  both)
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry"
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image-ghcr.copyToRegistry"
    ;;
  *)
    echo "build-postgres18-cnpg-image.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

./scripts/smoke-image.sh "${push_image}" "$INTERNAL_TAG"
echo "$INTERNAL_TAG"
