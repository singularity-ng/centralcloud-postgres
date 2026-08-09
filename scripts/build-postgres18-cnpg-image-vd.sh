#!/usr/bin/env bash
# Build the VectorDrive PostgreSQL 18 CNPG image (owned pgrx + shared operations).
#
# Prerequisites:
#   Package vectordrive extensions into nix/vectordrive-ext/ (or set
#   VECTORDRIVE_EXT_PATH to that directory) before building.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation without publishing
#   PUSH=1            — copy to the internal registry only
#                       (registry.centralcloud.net/singularity-ng/vectordrive-postgres:18-cnpg)
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

if [[ -z "${VECTORDRIVE_EXT_PATH:-}" ]]; then
  echo "build-postgres18-cnpg-image-vd.sh: VECTORDRIVE_EXT_PATH must point to the six-extension package output" >&2
  exit 1
fi
if [[ ! -d "$VECTORDRIVE_EXT_PATH/lib" || ! -d "$VECTORDRIVE_EXT_PATH/share/extension" ]]; then
  echo "build-postgres18-cnpg-image-vd.sh: invalid VECTORDRIVE_EXT_PATH=$VECTORDRIVE_EXT_PATH" >&2
  exit 1
fi
nix_build_args+=(--impure)

internal_tag="registry.centralcloud.net/singularity-ng/vectordrive-postgres:18-cnpg"
ghcr_tag="ghcr.io/singularity-ng/vectordrive-postgres:18-cnpg"

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
    ./scripts/smoke-image.sh 1 "$internal_tag"
    ;;
  0)
    ;;
  *)
    echo "build-postgres18-cnpg-image-vd.sh: unknown SMOKE=$smoke (expected 0 or 1)" >&2
    exit 2
    ;;
esac

echo "$internal_tag"
