#!/usr/bin/env bash
# Smoke for atlas_migrate_diff_run: exercises the rule end-to-end
# against a real rules_pg `pg_server`, asserts a non-empty
# migration .sql file is emitted with a `CREATE TABLE` statement.
#
# Strategy:
#   1. The fixture (atlas.hcl + schema.hcl + migrations/) is staged in
#      runfiles. Copy it into a writable workdir under $TEST_TMPDIR
#      because `atlas migrate diff` writes into the migrations
#      directory.
#   2. `cd` into the workdir and invoke the migrate-diff_target
#      wrapper. It launches pg_server in the background, waits for
#      the env file, expands the URL template, exec's atlas migrate
#      diff with our `--name initial` argv passthrough.
#   3. Assert: migrations/ now contains a non-empty `*_initial.sql`
#      with a `CREATE TABLE "items"` statement.
set -euo pipefail

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -n "${TEST_SRCDIR:-}" ]]; then
    RUNFILES_DIR="$TEST_SRCDIR"
  elif [[ -d "${0}.runfiles" ]]; then
    RUNFILES_DIR="${0}.runfiles"
  fi
  export RUNFILES_DIR
fi

resolve() {
  local p="$1"
  if [[ -e "${RUNFILES_DIR}/_main/${p}" ]]; then
    printf '%s\n' "${RUNFILES_DIR}/_main/${p}"
  elif [[ -e "${RUNFILES_DIR}/${p}" ]]; then
    printf '%s\n' "${RUNFILES_DIR}/${p}"
  else
    echo "smoke: input not in runfiles: ${p}" >&2
    exit 1
  fi
}

# The atlas_migrate_diff_run rule declare_file's the wrapper as
# `<name>.sh` (matches rules_opa's pattern). The bazel target name
# stays `migrate-diff` for `bazel run`, but the on-disk file in the
# runfiles tree carries the `.sh` suffix.
DIFF_RUN_BIN="$(resolve tests/migrate_diff_smoke/migrate-diff.sh)"
ATLAS_HCL="$(resolve tests/migrate_diff_smoke/atlas.hcl)"
SCHEMA_HCL="$(resolve tests/migrate_diff_smoke/schema.hcl)"

# Stage a writable workdir. atlas migrate diff writes into
# migrations/ — runfiles are read-only, so we cp+cd into TEST_TMPDIR.
work="${TEST_TMPDIR}/work"
mkdir -p "$work/migrations"
cp "$ATLAS_HCL" "$work/atlas.hcl"
cp "$SCHEMA_HCL" "$work/schema.hcl"

cd "$work"
echo "smoke: invoking migrate-diff wrapper in $work"
# Atlas migrate diff takes the migration name as a positional arg
# (`atlas migrate diff <name>`), not a `--name` flag.
"$DIFF_RUN_BIN" initial

# Assert exactly one migration file was emitted, named
# <ts>_initial.sql, with a CREATE TABLE statement for `items`.
shopt -s nullglob
emitted=( migrations/*_initial.sql )
if (( ${#emitted[@]} != 1 )); then
  echo "smoke: FAIL — expected exactly one *_initial.sql in migrations/, got ${#emitted[@]}" >&2
  ls -la migrations/ >&2 || true
  exit 1
fi

migration="${emitted[0]}"
if [[ ! -s "$migration" ]]; then
  echo "smoke: FAIL — emitted migration file is empty: $migration" >&2
  exit 1
fi

if ! grep -qiE 'CREATE TABLE.*items' "$migration"; then
  echo "smoke: FAIL — emitted migration missing CREATE TABLE \"items\"" >&2
  echo "---- $migration ----" >&2
  cat "$migration" >&2
  exit 1
fi

echo "smoke: OK — atlas_migrate_diff_run emitted a valid migration:"
echo "  $migration"
echo "  $(wc -l < "$migration") lines, $(wc -c < "$migration") bytes"
echo "  preview:"
sed 's/^/    /' "$migration"
