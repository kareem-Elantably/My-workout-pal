#!/usr/bin/env bash
# Loads db/schema.sql into a throwaway Postgres 16 (with Supabase stand-ins)
# and runs db/test/tests.sql. Needs the Postgres 16 server binaries.
#   PGBIN=/usr/lib/postgresql/16/bin db/test/run.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
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

cp "$here/supabase_stub.sql" "$here/../schema.sql" "$here/tests.sql" "$tmp/"
chmod 644 "$tmp"/*.sql
as_pg "$pgbin/initdb -D $tmp/data -U postgres -E UTF8 --locale=C.UTF-8" >/dev/null
as_pg "$pgbin/pg_ctl -D $tmp/data -l $tmp/log -w -o \"-k $tmp -p $port -c listen_addresses= -c timezone=UTC\" start" >/dev/null

as_pg "cd / && psql -h $tmp -p $port -U postgres -q -X -o /dev/null -v ON_ERROR_STOP=1 \
  -f $tmp/supabase_stub.sql -f $tmp/schema.sql -f $tmp/tests.sql"
