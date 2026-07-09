# Agent Notes - CentralCloud Postgres

## Purpose

This repo owns the CentralCloud PostgreSQL 18 CloudNativePG operand image and
its packaged extension set. Runtime `Cluster` manifests live in `/srv/infra`.

## Owned Paths

- `flake.nix`: image inputs, base CNPG image, OCI labels, optional VectorDrive
  image.
- `flake.lock`: pinned Nix inputs. Keep `nixpkgs` on `nixos-26.05` unless the
  fleet OS channel changes.
- `nix/postgres18-extensions.nix`: extension package overrides and bundle root.
- `nix/pgaudit-pg18.nix`: PostgreSQL 18 pgaudit build.
- `extensions.json`: extension catalog used for generated docs.
- `images/postgres18-cnpg/*.json`: pinned CNPG base image manifests.
- `scripts/build-postgres18-cnpg-image.sh`: local and CI image build/push path.
- `scripts/smoke-image.sh`: skopeo-based registry metadata smoke test.

## Rules

- Image files available is not the same as extension enabled. A database still
  needs preload settings when required and `CREATE EXTENSION` in the target DB.
- Do not mutate live databases from this repo unless the user explicitly asks
  for a live fix. Prefer GitOps manifests and migrations for durable changes.
- Rebuild/publish a new image when package sources, hashes, base image manifest,
  runtime libraries, or Nix inputs change. A SQL-only fix does not update the
  image.
- Keep one fleet image unless there is a measured size, licensing, or runtime
  reason to split. Extension files available in the image are not enabled until
  a database sets required preload libraries and runs `CREATE EXTENSION`.
  Keep API-fragile extensions such as `pg_duckdb` tied to build proof against
  the locked `nixos-26.05` DuckDB before changing versions or patching strategy.
- Before changing versions, check upstream release state and local consumers.
  Record any extension deliberately held behind latest with reason and falsifier.
- Keep CNPG base image digest-pinned. If adopting CNPG catalogs, update
  `/srv/infra` consumers intentionally; do not silently switch this image to a
  floating tag.
- Do not remove compatibility symlinks for restored TimescaleDB catalogs unless
  all live clusters have been checked for matching extension versions.

## Verification

Run narrow checks before claiming image work is ready:

```bash
nix flake check /home/mhugo/code/centralcloud-postgres
nix build /home/mhugo/code/centralcloud-postgres#postgresql-18-extension-bundle-platform
nix build /home/mhugo/code/centralcloud-postgres#postgresql-18-cnpg-image
```

After building or publishing an image, run:

```bash
/home/mhugo/code/centralcloud-postgres/scripts/smoke-image.sh <image>
kubectl -n databases get clusters.postgresql.cnpg.io \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.imageName}{"\t"}{.status.image}{"\n"}{end}'
```

For AGE specifically, verify both image and database state:

```sql
select * from pg_available_extensions where name = 'age';
select extversion from pg_extension where extname = 'age';
LOAD 'age';
```

## Maintenance Trigger

Update this file when image ownership, extension policy, live DB mutation rules,
verification commands, or `/srv/infra` handoff paths change.
