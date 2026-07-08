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

## Packages And Image

- `postgresql-18-extension-bundle-platform`: fleet extension files and generated catalog.
- `postgresql-18-extension-closure`: runtime closure for the platform bundle.
- `postgresql-18-cnpg-image`: CloudNativePG operand image tagged `18-cnpg-ext`.

There is one published operand image. It carries the buildable extension files
so clusters can share one image, but databases still opt in with
`shared_preload_libraries` and `CREATE EXTENSION`.

`pg_duckdb` is included and patched to build against the locked `nixos-26.05`
DuckDB `1.5.2` library. It is only available in the image; databases must still
set `shared_preload_libraries = 'pg_duckdb'` and run `CREATE EXTENSION`.

The platform image includes:

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
- pg_ivm
- pg_duckdb
- wrappers
- RUM
- hypopg
- pg_hint_plan
- plpgsql_check
- pg_trgm
- unaccent
- btree_gin
- btree_gist
- pgstattuple
- amcheck
- pageinspect
- postgres_fdw
- pgcrypto
- pg_prewarm
- pgaudit
- PL/Python runtime files

The packages make extensions available. Databases still choose their own
`shared_preload_libraries` and `CREATE EXTENSION` list.

The PostgreSQL base image also includes preloadable contrib modules such as
`auto_explain`. These are verified by smoke tests but are not listed as SQL
extensions because they do not have `CREATE EXTENSION` control files.

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
| `pg_ivm` | `pg_ivm` | Yes | No | No | Incremental materialized view maintenance — refreshes only changed rows instead of full REFRESH. High value for analytics aggregations (finops cost rollups, dashboards) that would otherwise need full recompute on every write. |
| `pg_duckdb` | `pg_duckdb` | Yes | `pg_duckdb` | No | DuckDB-powered in-process OLAP analytics. Built against the locked nixos-26.05 DuckDB 1.5.2 library; databases must opt in with shared_preload_libraries and CREATE EXTENSION. |
| `wrappers` | `wrappers` | Yes | No | No | Supabase FDW collection — S3/Garage, Stripe, BigQuery, Firebase, Airtable, Clickhouse, Redis as foreign tables. Useful for finops collector reading from Garage S3 or external billing APIs directly via SQL. |
| `rum` | `rum` | Yes | No | No | RUM index access method — full-text search with timestamp ordering in a single index scan. Faster than GIN + ORDER BY ts_rank for time-sorted full-text queries. |
| `hypopg` | `hypopg` | Yes | No | No | Hypothetical indexes for query planning. |
| `pg_hint_plan` | `pg_hint_plan` | Yes | No | No | Planner hints for exceptional query tuning cases. |
| `plpgsql_check` | `plpgsql_check` | Yes | No | No | Static analysis and runtime checks for PL/pgSQL. |
| `pg_trgm` | `postgresql_18` | Yes | No | No | Core contrib trigram indexes and fuzzy text matching. |
| `unaccent` | `postgresql_18` | Yes | No | No | Core contrib accent-insensitive text normalization. |
| `btree_gin` | `postgresql_18` | Yes | No | No | Core contrib B-tree operator classes for GIN indexes. |
| `btree_gist` | `postgresql_18` | Yes | No | No | Core contrib B-tree operator classes for GiST indexes. |
| `pgstattuple` | `postgresql_18` | Yes | No | No | Core contrib table and index bloat inspection. |
| `amcheck` | `postgresql_18` | Yes | No | No | Core contrib index and relation corruption checks. |
| `pageinspect` | `postgresql_18` | Yes | No | No | Core contrib low-level page inspection for incident debugging. |
| `postgres_fdw` | `postgresql_18` | Yes | No | No | Core contrib foreign data wrapper for PostgreSQL-to-PostgreSQL access. |
| `pgcrypto` | `postgresql_18` | Yes | No | No | Core contrib cryptographic helpers and random data functions. |
| `pg_prewarm` | `postgresql_18` | Yes | No | No | Core contrib cache warming for important tables and indexes. |
| `pgaudit` | `pgaudit` | Yes | `pgaudit` | No | Detailed database audit logging. Preload and configure only where audit volume is acceptable. |
| `uuid-ossp` | `postgresql_18` | Yes | No | No | Legacy compat only. PG18 has gen_random_uuid() (v4) and uuidv7() as built-ins — no extension needed for new code. Enable only for existing apps calling uuid_generate_v4() that cannot be migrated. |
| `hstore` | `postgresql_18` | Yes | No | No | Core contrib key-value store type. Prefer JSONB for new code; enable for apps that use hstore columns. |
| `citext` | `postgresql_18` | Yes | No | No | Core contrib case-insensitive text type. Useful for email and username columns; simpler than lower() indexes. |
| `ltree` | `postgresql_18` | Yes | No | No | Core contrib hierarchical label tree type and operators. Efficient ancestor/descendant queries without recursive CTEs. |
| `intarray` | `postgresql_18` | Yes | No | No | Core contrib integer array functions and GiST/GIN indexes. Efficient set membership and intersection queries. |
| `pg_buffercache` | `postgresql_18` | Yes | No | No | Core contrib shared buffer cache inspection. Useful for diagnosing what is and isn't cached during performance investigation. |

<!-- extension-matrix:end -->

## CI Secrets

The Forgejo release workflow (`.forgejo/workflows/release.yml`) publishes
the operand image to both the internal CNPG registry and the public GHCR
mirror on every push to `main` and every `v*` tag. Required secrets
(repo → Settings → Actions → Secrets):

| Secret              | Required | Purpose                                                 |
|---------------------|----------|---------------------------------------------------------|
| `REGISTRY_USER`     | yes      | Forgejo user with write to `registry.infra.centralcloud.com` |
| `REGISTRY_PASSWORD` | yes      | That user's PAT or password                             |
| `GHCR_USER`         | optional | GitHub user with write to `ghcr.io/singularity-ng`      |
| `GHCR_TOKEN`        | optional | GitHub PAT with `write:packages` scope                  |

When `GHCR_USER` / `GHCR_TOKEN` are missing the workflow logs a
`::warning::`, publishes only to the internal registry, and continues.
Provision the GHCR secrets to keep the public mirror in sync (the SF
test harness defaults to the GHCR tag because the internal registry
requires VPN/cluster network).

To provision via the Forgejo CLI:

```sh
forgejo --token "$FORGEJO_PAT" -r centralcloud/centralcloud-postgres \
    secret set REGISTRY_USER "ci-runner"
forgejo --token "$FORGEJO_PAT" -r centralcloud/centralcloud-postgres \
    secret set REGISTRY_PASSWORD "$REGISTRY_PAT"
forgejo --token "$FORGEJO_PAT" -r centralcloud/centralcloud-postgres \
    secret set GHCR_USER "mikkihugo"
forgejo --token "$FORGEJO_PAT" -r centralcloud/centralcloud-postgres \
    secret set GHCR_TOKEN "$GHCR_PAT"
```

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

Build the fleet extension bundle:

```sh
just build-bundles
```

Build the OCI image with `nix2container`:

```sh
nix build .#postgresql-18-cnpg-image
```

Build the OCI image:

```sh
just build-images
```

The provided `just` and image-build commands disable private remote builders by
default so public builds do not accidentally SSH into CentralCloud hosts. Set
`USE_REMOTE_BUILDERS=1` only when intentionally using your own configured Nix
builders.

Build a CloudNativePG-compatible image:

```sh
just build-cnpg-image
```

Push the default platform image:

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
