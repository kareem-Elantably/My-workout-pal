#!/usr/bin/env bash
# Applies supabase/migrations/*.sql in order to a throwaway Postgres 16
# (with Supabase stand-ins) and runs db/test/tests.sql.
# Needs the Postgres 16 server binaries.
#   PGBIN=/usr/lib/postgresql/16/bin db/test/run.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
migrations="$here/../../supabase/migrations"
pgbin=${PGBIN:-/usr/lib/postgresql/16/bin}
tmp=$(mktemp -d)
port=54329

if [ "$(id -u)" = 0 ]; then
  chown postgres "$tmp"
  as_pg() { su postgres -c "$*"; }
else
  as_pg() { bash -c "$*"; }
fi

cleanup() { as_pg "$pgbin/pg_ctl -D $tmp/data stop -m fast" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

mkdir "$tmp/migrations"
cp "$here/supabase_stub.sql" "$here/tests.sql" "$tmp/"
cp "$migrations"/*.sql "$tmp/migrations/"
chmod -R a+rX "$tmp"
files="-f $tmp/supabase_stub.sql"
for m in "$tmp"/migrations/*.sql; do files="$files -f $m"; done

as_pg "$pgbin/initdb -D $tmp/data -U postgres -E UTF8 --locale=C.UTF-8" >/dev/null
as_pg "$pgbin/pg_ctl -D $tmp/data -l $tmp/log -w -o \"-k $tmp -p $port -c listen_addresses= -c timezone=UTC\" start" >/dev/null

as_pg "cd / && psql -h $tmp -p $port -U postgres -q -X -o /dev/null -v ON_ERROR_STOP=1 \
  $files -f $tmp/tests.sql"
