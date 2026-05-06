#!/usr/bin/env bash
set -euo pipefail

image="${1:-ghcr.io/singularity-ng/centralcloud-postgres:18-cnpg-ext}"

docker run --rm --entrypoint bash "$image" -lc '
  set -euo pipefail
  for control in \
    timescaledb.control \
    pg_stat_statements.control \
    vector.control \
    vchord.control \
    vchord_bm25.control \
    pg_tokenizer.control \
    age.control \
    pgmq.control \
    pg_cron.control \
    pg_repack.control \
    pg_partman.control \
    hypopg.control \
    pg_hint_plan.control \
    plpgsql_check.control \
    pg_trgm.control \
    unaccent.control \
    btree_gin.control \
    btree_gist.control \
    pgstattuple.control \
    amcheck.control \
    pageinspect.control \
    postgres_fdw.control \
    pgcrypto.control \
    pg_prewarm.control \
    pgaudit.control; do
    test -f "/usr/share/postgresql/18/extension/$control"
  done
  test -f "/usr/lib/postgresql/18/lib/auto_explain.so"
  /usr/lib/postgresql/18/bin/postgres --version
'
