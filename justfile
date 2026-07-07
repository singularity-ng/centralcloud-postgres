set shell := ["bash", "-euo", "pipefail", "-c"]

# Fast lint (shell + workflows + docs). Nix format/lint runs in lefthook pre-commit
# and in `nix flake check` via `just check`.
lint:
    ./scripts/generate-extension-docs.py --check
    just lint-workflows
    just lint-shell

lint-workflows:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=(.forgejo/workflows/*.{yml,yaml} .github/workflows/*.{yml,yaml})
    if ((${#files[@]})); then
      actionlint -config-file .github/actionlint.yaml "${files[@]}"
    fi

lint-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=(scripts/*.sh)
    if ((${#files[@]})); then
      shellcheck -S error "${files[@]}"
    fi

check:
    nix flake check --option builders ""

docs:
    ./scripts/generate-extension-docs.py

build-bundle:
    nix build --option builders "" .#postgresql-18-extension-bundle --no-link

build-image:
    nix build --option builders "" .#postgresql-18-cnpg-image --no-link

smoke-image:
    ./scripts/smoke-image.sh

build-cnpg-image:
    ./scripts/build-postgres18-cnpg-image.sh

push-cnpg-image:
    PUSH=1 ./scripts/build-postgres18-cnpg-image.sh

# Push to BOTH the internal CNPG registry AND the GHCR public mirror.
# Use when operators need off-cluster access (CI matrices, dev laptops
# without VPN) — keeps both digests in sync.
push-cnpg-image-mirror:
    PUSH=both ./scripts/build-postgres18-cnpg-image.sh

build-cnpg-image-vd:
    @echo "vectordrive image script not vendored yet; use: nix build .#postgresql-18-cnpg-image-vd" >&2
    @exit 1

push-cnpg-image-vd:
    @echo "see build-cnpg-image-vd" >&2
    @exit 1

push-cnpg-image-vd-mirror:
    @echo "see build-cnpg-image-vd" >&2
    @exit 1

sbom:
    mkdir -p dist
    nix shell nixpkgs#syft -c syft registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext -o spdx-json=dist/sbom.spdx.json

install-hooks:
    lefthook install

fmt:
    nix fmt

# Local CNPG dev cluster (k3d + CNPG). Same image digest as prod, primary
# + replica, port-forwarded to localhost:5432 (rw) and :5433 (ro).
# Use for replication/failover/PITR work. Day-to-day app dev uses the
# app repo's own database workflow for speed.
cluster-up:
    centralcloud-postgres-dev-cluster

cluster-down:
    centralcloud-postgres-dev-cluster --stop

cluster-chaos:
    centralcloud-postgres-dev-cluster --chaos
