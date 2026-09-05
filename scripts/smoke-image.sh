#!/usr/bin/env bash
# Image smoke checks without docker/skopeo in the dev shell.
#
# Usage:
#   smoke-image.sh [PUSH_MODE] [IMAGE_REF]
#
# PUSH_MODE=0 (or unset with no ref): nix flake check cnpg-image derivation
# PUSH_MODE=1|both + IMAGE_REF: remote label check when skopeo is on PATH (CI runner)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_mode="${1:-0}"
image="${2:-registry.centralcloud.net/centralcloud/centralcloud-postgres:18-cnpg-ext}"

if [[ "$push_mode" == "0" ]]; then
  nix build --option builders "" "$repo_root#postgresql-18-cnpg-image" --no-link
  exit 0
fi

if ! command -v skopeo >/dev/null 2>&1; then
  echo "smoke-image.sh: skopeo not on PATH; skipping remote inspect for $image" >&2
  echo "smoke-image.sh: CI runners provide skopeo; local dev uses PUSH=0 build check" >&2
  exit 0
fi

inspect_json="$(skopeo inspect "docker://$image")"
actual_profile="$(jq -r '.Labels["org.centralcloud.postgres.extension-profile"] // ""' <<<"$inspect_json")"

# Fail closed. This previously read `-n "$actual_profile" && ...`, so an image
# with NO labels - exactly what a zero-layer manifest looks like - skipped the
# comparison and exited 0. That is how a postgres image with no /bin/sh passed
# this check twice.
if [[ -z "$actual_profile" ]]; then
  echo "smoke-image.sh: image carries no extension-profile label at all" >&2
  echo "smoke-image.sh: refusing to treat an unlabelled image as verified" >&2
  exit 1
fi

if [[ "$actual_profile" != "platform" ]]; then
  echo "smoke-image.sh: expected profile=platform, got profile=$actual_profile" >&2
  exit 1
fi

layer_count="$(jq -r '(.LayersData // .Layers // []) | length' <<<"$inspect_json")"
if [[ "${layer_count:-0}" -lt 1 ]]; then
  echo "smoke-image.sh: published image reports $layer_count layers" >&2
  exit 1
fi

jq -r '.Digest' <<<"$inspect_json"
