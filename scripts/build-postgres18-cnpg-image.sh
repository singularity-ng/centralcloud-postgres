#!/usr/bin/env bash
# Build the CentralCloud PostgreSQL 18 CNPG image via nix2container.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation only (no publish)
#   PUSH=1            — skopeo copy → internal registry
#   PUSH=both         — internal registry, then GHCR mirror
#   USE_REMOTE_BUILDERS=1 — allow nix to dispatch to remote builders.
#
# Publish credentials (CI sets these from Forgejo/GitHub secrets):
#   REGISTRY_USER / REGISTRY_PASSWORD — internal registry
#   GHCR_USER / GHCR_TOKEN            — GHCR mirror (PUSH=both only)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_image="${PUSH:-0}"
use_remote_builders="${USE_REMOTE_BUILDERS:-0}"
nix_build_args=(--accept-flake-config)

INTERNAL_TAG="registry.centralcloud.net/centralcloud/centralcloud-postgres:18-cnpg-ext"
GHCR_TAG="ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext"

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

skopeo_copy() {
  local copy_tool="$1"
  local image_json="$2"
  local destination="$3"
  local user="$4"
  local password="$5"

  if [[ -z "$user" || -z "$password" ]]; then
    echo "build-postgres18-cnpg-image.sh: missing registry credentials for ${destination}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  (
    eval "$(grep '^export PATH=' "$copy_tool/bin/copy-to-registry")"
    skopeo --insecure-policy copy \
      --dest-creds "${user}:${password}" \
      "nix:${image_json}" \
      "docker://${destination}"
  )
}

case "$push_image" in
  0)
    nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --no-link
    ;;
  1 | both)
    image_json="$(
      nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --print-out-paths --no-link
    )"
    copy_tool="$(
      nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry" --print-out-paths --no-link
    )"

    skopeo_copy "$copy_tool" "$image_json" "$INTERNAL_TAG" \
      "${REGISTRY_USER:-}" "${REGISTRY_PASSWORD:-}"

    if [[ "$push_image" == "both" ]]; then
      skopeo_copy "$copy_tool" "$image_json" "$GHCR_TAG" \
        "${GHCR_USER:-}" "${GHCR_TOKEN:-}"
    fi
    ;;
  *)
    echo "build-postgres18-cnpg-image.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

./scripts/smoke-image.sh "${push_image}" "$INTERNAL_TAG"
echo "$INTERNAL_TAG"
