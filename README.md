# CentralCloud PostgreSQL

Shared PostgreSQL packaging for CentralCloud services and public
CloudNativePG users who need a richer PostgreSQL 18 extension set.

This repo owns PostgreSQL 18 extension packaging and CloudNativePG image build
inputs. Application repos should consume this repo instead of carrying local
PostgreSQL extension overlays.

The repo is intended to be useful outside CentralCloud too: it publishes a Nix
flake for reproducible builds and a GHCR image for Kubernetes users who want a
ready CloudNativePG operand image with a broader extension set than the upstream
base image.

## Packages

- `postgresql-18-extension-bundle`: PostgreSQL 18 extension files and generated catalog.
- `postgresql-18-extension-closure`: runtime closure for the extension bundle.

Included extension packages:

- TimescaleDB
- pgvector
- VectorChord
- VectorChord BM25
- pg_tokenizer
- Apache AGE
- pgmq
- pg_cron
- pg_repack
- pg_partman
- hypopg
- pg_hint_plan
- plpgsql_check

The packages make extensions available. Databases still choose their own
`shared_preload_libraries` and `CREATE EXTENSION` list.

## Extension Matrix

<!-- extension-matrix:start -->

This section is generated from `extensions.json`.

| Extension | Package | Available | Preload required | Created by default | Notes |
| --- | --- | --- | --- | --- | --- |
| `timescaledb` | `timescaledb` | Yes | `timescaledb` | No | Required only for databases using TimescaleDB hypertables or compression. |
| `pg_stat_statements` | `postgresql_18` | Yes | `pg_stat_statements` | No | Core contrib extension available from the PostgreSQL base image. |
| `vector` | `pgvector` | Yes | No | No | Dense vector type and indexes. |
| `vchord` | `vectorchord` | Yes | `vchord` | No | VectorChord indexing extension. |
| `vchord_bm25` | `vchord-bm25` | Yes | `vchord_bm25` | No | BM25 sparse ranking. Usually used with pg_tokenizer. |
| `pg_tokenizer` | `pg-tokenizer` | Yes | `pg_tokenizer` | No | Tokenizer support for BM25 search. |
| `age` | `age` | Yes | `age` | No | Apache AGE graph database extension. |
| `pgmq` | `pgmq` | Yes | No | No | Postgres-backed message queues. |
| `pg_cron` | `pg_cron` | Yes | `pg_cron` | No | Requires cron.database_name for the database that owns jobs. |
| `pg_repack` | `pg_repack` | Yes | No | No | Online table and index reorganization. |
| `pg_partman` | `pg_partman` | Yes | No | No | Partition management extension. |
| `hypopg` | `hypopg` | Yes | No | No | Hypothetical indexes for query planning. |
| `pg_hint_plan` | `pg_hint_plan` | Yes | No | No | Planner hints for exceptional query tuning cases. |
| `plpgsql_check` | `plpgsql_check` | Yes | No | No | Static analysis and runtime checks for PL/pgSQL. |

<!-- extension-matrix:end -->

## Public Artifacts

- GitHub source repository with pinned Nix inputs.
- Nix overlay for NixOS and flake consumers.
- Nix-built extension bundle with an `extensions.json` catalog.
- Nix-built CloudNativePG-compatible PostgreSQL 18 OCI image.
- Published GHCR image for Kubernetes users.
- Validation script that checks required control files and PostgreSQL version.
- CI for Nix formatting, linting, generated docs, flake checks, and image builds.
- Release workflow for GHCR publishing, SBOM artifacts, and keyless cosign signing.

Default image:

```text
ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext
```

This is a PostgreSQL operand image for CloudNativePG pods. It does not install
CloudNativePG itself.

## Build

```sh
nix build .#postgresql-18-extension-bundle
```

Build the OCI image with `nix2container`:

```sh
nix build .#postgresql-18-cnpg-image
```

Load the image into the local Docker daemon:

```sh
nix run .#postgresql-18-cnpg-image.copyToDockerDaemon
```

The provided `just` and image-build commands disable private remote builders by
default so public builds do not accidentally SSH into CentralCloud hosts. Set
`USE_REMOTE_BUILDERS=1` only when intentionally using your own configured Nix
builders.

Build and load a CloudNativePG-compatible image:

```sh
just build-cnpg-image
```

Push the image:

```sh
PUSH=1 just build-cnpg-image
```

The image tag starts with `18` because CloudNativePG validates the image major
version from the tag.

Generate an SBOM for the loaded image:

```sh
just sbom
```

The default SBOM output is `dist/sbom.spdx.json`.

Release builds sign the GHCR image with keyless Sigstore/cosign using GitHub
OIDC and attach the SBOM to the image.

## Consumer Usage

For NixOS configs, import `nix/postgres18-extensions.nix` and add
`postgres18.overlay` to `nixpkgs.overlays`.

```nix
let
  postgres18 = import ./path/to/postgres18-extensions.nix {};
in {
  nixpkgs.overlays = [
    postgres18.overlay
  ];
}
```

For CloudNativePG, use the published image and enable only the extensions needed
by that cluster.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-postgres
spec:
  imageName: ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext
  postgresql:
    shared_preload_libraries:
      - timescaledb
    parameters:
      pg_stat_statements.track: all
```

For a database that needs dense and sparse vector search, add the relevant
preload libraries and create the extensions in that database only:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord;
CREATE EXTENSION IF NOT EXISTS pg_tokenizer;
CREATE EXTENSION IF NOT EXISTS vchord_bm25 CASCADE;
```
