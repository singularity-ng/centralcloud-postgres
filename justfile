set shell := ["bash", "-euo", "pipefail", "-c"]

check:
    alejandra --check flake.nix nix
    statix check .
    deadnix flake.nix nix
    ./scripts/generate-extension-docs.py --check
    nix flake check --option builders ""

docs:
    ./scripts/generate-extension-docs.py

build-bundle:
    nix build --option builders "" .#postgresql-18-extension-bundle --no-link

build-image:
    nix build --option builders "" .#postgresql-18-cnpg-image --no-link

load-cnpg-image:
    nix run --option builders "" .#postgresql-18-cnpg-image.copyToDockerDaemon

smoke-image:
    ./scripts/smoke-image.sh

build-cnpg-image:
    ./scripts/build-postgres18-cnpg-image.sh

push-cnpg-image:
    PUSH=1 ./scripts/build-postgres18-cnpg-image.sh

sbom:
    mkdir -p dist
    syft registry.infra.centralcloud.com/centralcloud/centralcloud-postgres:18-cnpg-ext -o spdx-json=dist/sbom.spdx.json

install-hooks:
    lefthook install

fmt:
    alejandra flake.nix nix
