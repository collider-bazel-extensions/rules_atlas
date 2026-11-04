#!/usr/bin/env bash
# An empty migration set with allow_empty = True passes, saying so.
set -euo pipefail
out=$("$1" 2>&1) || { echo "FAIL: exited $?: $out" >&2; exit 1; }
echo "$out"
grep -q "no migrations to lint (allow_empty = True); passing" <<<"$out" || { echo "FAIL: no note" >&2; exit 1; }
echo "PASS"
