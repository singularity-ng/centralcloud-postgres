#!/usr/bin/env bash
# Build the CentralCloud PostgreSQL 18 CNPG image.
#
# Modes (env vars):
#   PUSH=0  (default) — copy to local Docker daemon for smoke testing
#   PUSH=1            — copy to the internal registry only
#                       (registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext)
#   PUSH=both         — copy to BOTH the internal registry AND the GHCR mirror
#                       (ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext)
#                       — used by CI and any operator manually re-syncing the public mirror.
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

case "$push_image" in
  0)
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToDockerDaemon"
    ;;
  1)
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry"
    ;;
  both)
    # Internal registry first (matches operand image used by the
    # sf-postgres CNPG cluster), then mirror to GHCR for off-cluster
    # access (e.g. CI matrix in repos that can't reach the internal
    # registry).
    nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry"
    # Re-tag the daemon-loaded image isn't sufficient because we built
    # via nix2container.copyToRegistry which doesn't go through the daemon.
    # Instead, use skopeo to copy registry→registry — fast (digest-based),
    # auth from each registry's local docker config.
    skopeo copy --quiet \
      "docker://$INTERNAL_TAG" \
      "docker://$GHCR_TAG"
    ;;
  *)
    echo "build-postgres18-cnpg-image.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

./scripts/smoke-image.sh "$INTERNAL_TAG"
echo "$INTERNAL_TAG"
