#!/usr/bin/env bash
# Applique les migrations sur une base jetable et lance les assertions.
#   PGURL="postgres://user:pass@host:5432/postgres" ./db/_test/run.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
PGURL="${PGURL:-postgres://postgres@localhost:5432/postgres}"
DB="${TF_TEST_DB:-tablefinder_test}"

psql "$PGURL" -v ON_ERROR_STOP=1 -q \
  -c "drop database if exists ${DB};" \
  -c "create database ${DB};"

TARGET="${PGURL%/*}/${DB}"
run() { echo "==> $(basename "$1")"; psql "$TARGET" -v ON_ERROR_STOP=1 -q -f "$1"; }

run "$HERE/00_roles.sql"
for f in "$ROOT"/migrations/*.sql; do run "$f"; done
run "$HERE/_assert.sql"
run "$HERE/01_checks.sql"
run "$HERE/02_rls_and_import.sql"

echo; echo "Toutes les assertions sont passées."

