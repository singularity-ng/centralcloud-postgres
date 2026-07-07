#!/usr/bin/env bash
# Build the CentralCloud PostgreSQL 18 CNPG image via nix2container.
#
# Modes (env vars):
#   PUSH=0  (default) — build the OCI image derivation only (no publish)
#   PUSH=1            — copyToRegistry → internal registry
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

INTERNAL_TAG="registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext"
GHCR_TAG="ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext"

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

push_with_creds() {
  local attr="$1"
  local user="$2"
  local password="$3"

  if [[ -z "$user" || -z "$password" ]]; then
    echo "build-postgres18-cnpg-image.sh: missing registry credentials for ${attr}" >&2
    exit 1
  fi

  # nix2container's skopeo supports the nix: transport; pass --dest-creds
  # because runner authfiles are not visible inside nix run's sandbox.
  nix run --impure "${nix_build_args[@]}" \
    "$repo_root#${attr}.copyToRegistry" -- \
    --dest-creds "${user}:${password}"
}

case "$push_image" in
  0)
    nix build "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image" --no-link
    ;;
  1)
    push_with_creds postgresql-18-cnpg-image \
      "${REGISTRY_USER:-}" "${REGISTRY_PASSWORD:-}"
    ;;
  both)
    push_with_creds postgresql-18-cnpg-image \
      "${REGISTRY_USER:-}" "${REGISTRY_PASSWORD:-}"
    push_with_creds postgresql-18-cnpg-image-ghcr \
      "${GHCR_USER:-}" "${GHCR_TOKEN:-}"
    ;;
  *)
    echo "build-postgres18-cnpg-image.sh: unknown PUSH=$push_image (expected 0, 1, or both)" >&2
    exit 2
    ;;
esac

./scripts/smoke-image.sh "${push_image}" "$INTERNAL_TAG"
echo "$INTERNAL_TAG"
