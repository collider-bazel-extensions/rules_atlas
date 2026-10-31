#!/usr/bin/env bash
# Runs an atlas_migrate_lint_test target that must fail and checks that its
# output names the expected diagnostic code.
#   $1  rootpath of the lint test's executable
#   $2  diagnostic code that must appear (e.g. MF103)
set -euo pipefail

lint="$1"
code="$2"
out="${TEST_TMPDIR}/lint.out"

if "$lint" >"$out" 2>&1; then
  cat "$out" >&2
  echo "FAIL: $lint passed; expected a failure reporting $code" >&2
  exit 1
fi
cat "$out"
if ! grep -q ": ${code}: " "$out"; then
  echo "FAIL: $lint failed but its output does not name $code" >&2
  exit 1
fi
echo "ok: $lint failed with $code"
