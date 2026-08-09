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

if [[ -n "$actual_profile" && "$actual_profile" != "platform" ]]; then
  echo "smoke-image.sh: expected profile=platform, got profile=$actual_profile" >&2
  exit 1
fi

jq -r '.Digest' <<<"$inspect_json"
