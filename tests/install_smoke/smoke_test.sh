#!/usr/bin/env bash
# Full E2E install smoke for atlas_operator_install. Strategy:
#
#   1. Apply tests/install_smoke/cluster.yaml (Namespace + Secret +
#      CNPG Cluster + AtlasSchema CR pointing at the cluster URL).
#   2. Wait CNPG Cluster.status.phase == "Cluster in healthy state"
#      (or at least 1 instance Ready). The CNPG operator runs
#      bootstrap initdb (creates database `app` + role `app`) and
#      brings up a Postgres pod.
#   3. Wait AtlasSchema/smoke-schema status condition Ready=True.
#      Atlas Operator opens the postgres URL, plans the diff, and
#      applies it.
#   4. kubectl exec into the Postgres pod and verify the `users`
#      table exists with the expected columns.
#
# Proves end-to-end: CNPG-managed Postgres + Atlas Operator install
# + AtlasSchema reconciliation against a real database.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

NS="atlas-smoke"
PG_CLUSTER="smoke-pg"
ATLAS_SCHEMA="smoke-schema"

_resolve() {
  local rel="$1"
  for cand in \
    "${RUNFILES_DIR:-}/_main/$rel" \
    "$(dirname "$0").runfiles/_main/$rel" \
    "$rel"; do
    [[ -f "$cand" ]] && { echo "$cand"; return 0; }
  done
  return 1
}

CLUSTER_YAML="$(_resolve tests/install_smoke/cluster.yaml)" \
    || { echo "smoke: cluster.yaml not in runfiles" >&2; exit 1; }
ATLASSCHEMA_YAML="$(_resolve tests/install_smoke/atlasschema.yaml)" \
    || { echo "smoke: atlasschema.yaml not in runfiles" >&2; exit 1; }

echo "smoke: applying pre-fixture (CNPG Cluster + dev-DB) $CLUSTER_YAML"
"${KCTL[@]}" apply --server-side -f "$CLUSTER_YAML" >/dev/null

# Wait for the CNPG Cluster to come up. CNPG's status surface uses
# `.status.phase` strings; "Cluster in healthy state" is the
# steady-state. Falling back to readyInstances ≥ 1 covers the
# transitional phases on slow CI.
echo "smoke: waiting for CNPG Cluster/$PG_CLUSTER to become healthy"
deadline=$(( $(date +%s) + 360 ))
healthy=""
while (( $(date +%s) < deadline )); do
  ready=$("${KCTL[@]}" -n "$NS" get cluster.postgresql.cnpg.io "$PG_CLUSTER" \
      -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)
  phase=$("${KCTL[@]}" -n "$NS" get cluster.postgresql.cnpg.io "$PG_CLUSTER" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "${ready:-0}" -ge 1 ]] && [[ "$phase" == "Cluster in healthy state" ]]; then
    healthy=1
    break
  fi
  sleep 5
done
if [[ -z "$healthy" ]]; then
  echo "smoke: FAIL — CNPG Cluster never reached healthy (phase=${phase:-<unset>}, ready=${ready:-<unset>})" >&2
  "${KCTL[@]}" -n "$NS" get cluster.postgresql.cnpg.io "$PG_CLUSTER" -o yaml >&2 || true
  "${KCTL[@]}" -n "$NS" get pods -o wide >&2 || true
  exit 1
fi

# Wait for the hand-rolled atlas-devdb to become Ready. The
# Deployment has a pg_isready readiness probe so Available implies
# postgres is accepting connections — only THEN can the AtlasSchema
# safely reconcile (the operator stalls permanently after a single
# connect-refused).
echo "smoke: waiting for atlas-devdb Deployment to be Available"
"${KCTL[@]}" -n "$NS" wait deploy/atlas-devdb \
    --for=condition=Available --timeout=180s

# Now apply the AtlasSchema. Both the target and the dev URL accept
# connections, so the operator's first reconcile succeeds.
echo "smoke: applying AtlasSchema $ATLASSCHEMA_YAML"
"${KCTL[@]}" apply --server-side -f "$ATLASSCHEMA_YAML" >/dev/null

# Wait for AtlasSchema to reach Ready. The operator auto-provisions
# a "dev DB" Deployment (smoke-schema-atlas-dev-db) on first reconcile
# for diff planning — that's a cold postgres image pull + boot, which
# adds ~60s on first runs. Bumping deadline to 360s; the typical
# warm-cache run lands in <90s.
echo "smoke: waiting for AtlasSchema/$ATLAS_SCHEMA to reach Ready"
deadline=$(( $(date +%s) + 360 ))
ready=""
while (( $(date +%s) < deadline )); do
  ready=$("${KCTL[@]}" -n "$NS" get atlasschema "$ATLAS_SCHEMA" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]] && break
  sleep 5
done
if [[ "$ready" != "True" ]]; then
  echo "smoke: FAIL — AtlasSchema never reached Ready (status=${ready:-<unset>})" >&2
  echo "---- AtlasSchema status ----" >&2
  "${KCTL[@]}" -n "$NS" get atlasschema "$ATLAS_SCHEMA" -o yaml >&2 || true
  echo "---- pods (-n $NS) ----" >&2
  "${KCTL[@]}" -n "$NS" get pods -o wide >&2 || true
  echo "---- dev-db deploy (if any) ----" >&2
  "${KCTL[@]}" -n "$NS" describe deploy "${ATLAS_SCHEMA}-atlas-dev-db" >&2 || true
  echo "---- atlas-operator logs ----" >&2
  "${KCTL[@]}" -n atlas-operator-system logs deploy/atlas-operator --tail=300 >&2 || true
  exit 1
fi

# Verify the schema actually landed: kubectl exec into the postgres
# instance Pod (CNPG names it `<cluster>-1`) and run `\d users`.
# Connect via TCP `127.0.0.1` rather than the default Unix socket —
# CNPG's pg_hba.conf uses peer auth on the local socket, which
# requires the OS user calling psql to match the DB user. The
# postgres container runs as user `postgres` (UID 26); to log in as
# `app` we need TCP+password instead.
echo "smoke: verifying users table via kubectl exec psql"
psql_out=$("${KCTL[@]}" -n "$NS" exec "${PG_CLUSTER}-1" -c postgres -- \
    env PGPASSWORD=smoke-fixture-atlas-cnpg \
    psql -h 127.0.0.1 -U app -d app -t -c "\d users" 2>&1) || {
  echo "smoke: FAIL — psql \\d users failed:" >&2
  echo "$psql_out" >&2
  exit 1
}

if ! grep -q '\bid\b' <<<"$psql_out" || ! grep -q '\bname\b' <<<"$psql_out"; then
  echo "smoke: FAIL — \\d users missing expected columns. Got:" >&2
  echo "$psql_out" >&2
  exit 1
fi

echo "smoke: OK — Atlas Operator install + AtlasSchema reconciliation against live CNPG Postgres confirmed"
echo "  schema: $ATLAS_SCHEMA"
echo "  table excerpt:"
echo "$psql_out" | sed 's/^/    /'
