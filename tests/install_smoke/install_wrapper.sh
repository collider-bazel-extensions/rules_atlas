#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
INSTALL_BIN="${RUNFILES_DIR}/_main/tests/install_smoke/atlas_install_bin.sh"
[[ -x "$INSTALL_BIN" ]] || { echo "wrapper: atlas_install_bin not at $INSTALL_BIN" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

# Diagnostic dump on install failure: pull operator deployment +
# pod state + logs. Saves a 30-min CI stall when the operator
# image pull or RBAC fails silently.
on_install_fail() {
  local rc=$?
  echo "===== install_wrapper: atlas_install_bin exited $rc — dumping cluster state =====" >&2
  echo "---- pods/deploy (-n atlas-operator-system) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n atlas-operator-system get pods,deploy -o wide >&2 || true
  echo "---- describe deploy/atlas-operator ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n atlas-operator-system describe deploy/atlas-operator >&2 || true
  echo "---- logs deploy/atlas-operator ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n atlas-operator-system logs deploy/atlas-operator --tail=200 >&2 || true
  exit "$rc"
}
trap on_install_fail ERR

"$INSTALL_BIN"
