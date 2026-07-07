#!/usr/bin/env bash
# Build the CentralCloud PostgreSQL 18 CNPG image via nix2container.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation only (no publish)
#   PUSH=1            — skopeo copy → internal registry
#   PUSH=both         — internal registry, then GHCR mirror
#   USE_REMOTE_BUILDERS=1 — allow nix to dispatch to remote builders.
#
# Publish uses host skopeo with REGISTRY_AUTH_FILE (from CI login), not
# nix run copyToRegistry — the latter runs skopeo in a sandbox that cannot
# read the runner's authfile.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_image="${PUSH:-0}"
use_remote_builders="${USE_REMOTE_BUILDERS:-0}"
nix_build_args=(--accept-flake-config)

INTERNAL_TAG="registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext"
GHCR_TAG="ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext"

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

skopeo_copy() {
  local image_json="$1"
  local destination="$2"

  # REGISTRY_AUTH_FILE is set by CI after skopeo login; skopeo copy reads it
  # from the environment (there is no --authfile flag on copy).
  skopeo --insecure-policy copy "nix:${image_json}" "docker://${destination}"
}

case "$push_image" in
  0)
    nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --no-link
    ;;
  1 | both)
    if ! command -v skopeo >/dev/null 2>&1; then
      echo "build-postgres18-cnpg-image.sh: skopeo required for PUSH=${push_image}" >&2
      exit 1
    fi

    image_json="$(
      nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --print-out-paths --no-link
    )"
    skopeo_copy "$image_json" "$INTERNAL_TAG"

    if [[ "$push_image" == "both" ]]; then
      skopeo_copy "$image_json" "$GHCR_TAG"
    fi
    ;;
  *)
    echo "build-postgres18-cnpg-image.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

./scripts/smoke-image.sh "${push_image}" "$INTERNAL_TAG"
echo "$INTERNAL_TAG"
