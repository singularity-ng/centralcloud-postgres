#!/usr/bin/env bash
# Build the VectorDrive PostgreSQL 18 CNPG image (owned pgrx + vd-ops glue).
#
# Prerequisites:
#   Package vectordrive extensions into nix/vectordrive-ext/ (or set
#   VECTORDRIVE_EXT_PATH to that directory) before building.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation without publishing
#   PUSH=1            — copy to the internal registry only
#                       (registry.infra.centralcloud.com/singularity-ng/vectordrive-postgres:18-cnpg)
#   PUSH=both         — copy to BOTH the internal registry AND the GHCR mirror
#                       (ghcr.io/singularity-ng/vectordrive-postgres:18-cnpg)
#   USE_REMOTE_BUILDERS=1 — allow nix to dispatch to remote builders.
#   SMOKE=0|1             — optional skopeo registry metadata smoke after push.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_image="${PUSH:-0}"
use_remote_builders="${USE_REMOTE_BUILDERS:-0}"
smoke="${SMOKE:-0}"
nix_build_args=()

package="postgresql-18-cnpg-image-vd"

internal_tag="$(nix eval --raw "$repo_root#$package.passthru.imageRef")"
ghcr_tag="$(nix eval --raw "$repo_root#$package.passthru.ghcrImageRef")"

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

case "$push_image" in
  0)
    nix build "${nix_build_args[@]}" "$repo_root#$package" --no-link
    ;;
  1)
    nix run "${nix_build_args[@]}" "$repo_root#$package.copyToRegistry"
    ;;
  both)
    nix run "${nix_build_args[@]}" "$repo_root#$package.copyToRegistry"
    skopeo copy --quiet \
      "docker://$internal_tag" \
      "docker://$ghcr_tag"
    ;;
  *)
    echo "build-postgres18-cnpg-image-vd.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

case "$smoke" in
  1)
    ./scripts/smoke-image.sh "$internal_tag"
    ;;
  0)
    ;;
  *)
    echo "build-postgres18-cnpg-image-vd.sh: unknown SMOKE=$smoke (expected 0 or 1)" >&2
    exit 2
    ;;
esac

echo "$internal_tag"
