#!/usr/bin/env bash
# Builds a throwaway Postgres, applies the schema and the bot migrations, runs the SQL suite and
# exits non-zero if any scenario fails. Only needs Docker.
set -euo pipefail
cd "$(dirname "$0")/.."

compose() { docker compose "$@"; }
psql_as() { compose exec -T db psql -U "$1" -d cifro -v ON_ERROR_STOP=1 -q "${@:2}"; }

cleanup() { compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "==> Subindo o Postgres descartável"
compose up -d db >/dev/null
# The official image restarts once after initialising, so wait for the second "ready" line.
for _ in $(seq 1 60); do
  [ "$(compose logs db 2>&1 | grep -c 'ready to accept connections')" -ge 2 ] && break
  sleep 1
done
psql_as supabase_admin -c "select 1" >/dev/null

echo "==> Emulando o Supabase (papéis, auth.uid, privilégios padrão)"
psql_as supabase_admin < db/stub-supabase.sql

echo "==> Aplicando as migrations (schema do app e depois as do bot)"
for file in $(ls db/migrations/core/*.sql | sort) $(ls db/migrations/bot/*.sql | sort); do
  psql_as postgres < "$file" >/dev/null
  echo "    $(basename "$file")"
done

echo "==> Rodando a suíte"
# Each assertion is a `select`, which prints an empty row; the results table below is the real report.
cat db/tests/*.sql | psql_as postgres -At > /dev/null

psql_as postgres -At -F '  ' -c "
  select case when ok then 'PASS' else 'FAIL' end, scenario, name, coalesce(detail, '')
  from t.results order by id"

total=$(psql_as postgres -At -c "select count(*) from t.results")
failed=$(psql_as postgres -At -c "select count(*) from t.results where not ok")
echo
echo "RESULTADO: $((total - failed))/$total cenários passaram"

if [ "$total" -eq 0 ] || [ "$failed" -ne 0 ]; then
  exit 1
fi
