#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
push_image="${PUSH:-0}"
use_remote_builders="${USE_REMOTE_BUILDERS:-0}"
nix_build_args=()

if [[ "$use_remote_builders" != "1" ]]; then
  nix_build_args+=(--option builders "")
fi

if [[ "$push_image" == "1" ]]; then
  nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToRegistry"
else
  nix run "${nix_build_args[@]}" "$repo_root#postgresql-18-cnpg-image.copyToDockerDaemon"
fi

./scripts/smoke-image.sh registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext
echo "registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext"
