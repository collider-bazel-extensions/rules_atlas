#!/usr/bin/env bash
# Maintainer flow for adding/updating an Atlas Operator chart version:
#   1. Edit tools/versions.bzl::ATLAS_OPERATOR_VERSIONS — add the
#      target version's src_url + src_sha256 (compute via
#      `curl -fsL "<url>" | sha256sum`).
#   2. Add (or update) a `helm_template` + `sh_binary` block in
#      tools/BUILD.bazel for the new version.
#   3. tools/render_atlas_operator.sh <version>  (e.g. 0.7.29)
#
# Host helm is NOT required — helm comes from rules_helm.
set -euo pipefail

VERSION="${1:?usage: tools/render_atlas_operator.sh <version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_atlas_operator] $TARGET"
exec bazel run "$TARGET"
