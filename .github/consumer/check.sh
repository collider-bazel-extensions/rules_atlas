#!/usr/bin/env bash
# Consumer checks against the commit's release archive (git archive honours
# .gitattributes export-ignore, as GitHub's tag tarballs do):
#   1. no atlas.version() in the root resolves, and an atlas_schema_test runs
#      the default version (rules_atlas#12)
#   2. the same version set twice in the root resolves
#   3. an unsupported version fails, naming atlas.version
#   4. @rules_atlas//... loads (tests/ and tools/ are not shipped)
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
src="$work/rules_atlas"
rm -rf "$work"; mkdir -p "$src"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in tests tools; do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
default_version="$(sed -n 's/^DEFAULT_VERSION = "\(.*\)"$/\1/p' "$src/private/versions.bzl")"
kubectl_commit="$(grep -A3 'module_name = "rules_kubectl"' "$src/MODULE.bazel" | sed -n 's/.*commit = "\([0-9a-f]*\)".*/\1/p')"

consumer() { # <name> <extra MODULE.bazel lines>
    local c="$work/$1"
    mkdir -p "$c"
    touch "$c/BUILD.bazel"
    if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$c/"; fi
    cat > "$c/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "rules_atlas")
local_path_override(module_name = "rules_atlas", path = "$src")
bazel_dep(name = "rules_kubectl", version = "0.2.0")
git_override(
    module_name = "rules_kubectl",
    remote = "https://github.com/collider-bazel-extensions/rules_kubectl",
    commit = "$kubectl_commit",
)
$2
MOD
    cp "$repo/tests/schema_sqlite.hcl" "$c/schema.hcl"
    cat > "$c/BUILD.bazel" <<'BUILD'
load("@rules_atlas//:defs.bzl", "atlas_schema_test")

atlas_schema_test(
    name = "schema_test",
    srcs = ["schema.hcl"],
    mode = "validate",
)
BUILD
    echo "$c"
}

# 1. No atlas.version(): resolves; the registered toolchain's atlas runs.
c="$(consumer untagged "")"
(cd "$c" && bazel mod deps >/dev/null)
(cd "$c" && bazel test //:schema_test --test_output=errors)
bin="$(cd "$c" && bazel info output_base)/external/rules_atlas++atlas+atlas_linux_amd64/atlas"
"$bin" version | tee "$work/untagged.out"
grep -q "v$default_version" "$work/untagged.out" || { echo "FAIL: untagged consumer did not get atlas $default_version" >&2; exit 1; }
echo "PASS: untagged root resolves, atlas $default_version"

# 2. The same version twice in the root.
c="$(consumer twice "atlas = use_extension(\"@rules_atlas//:extensions.bzl\", \"atlas\")
atlas.version(version = \"$default_version\")
atlas.version(version = \"$default_version\")")"
(cd "$c" && bazel mod deps >/dev/null)
echo "PASS: repeated identical atlas.version resolves"

# 3. An unsupported version fails with a message naming atlas.version.
c="$(consumer unsupported 'atlas = use_extension("@rules_atlas//:extensions.bzl", "atlas")
atlas.version(version = "0.0.1")')"
if (cd "$c" && bazel mod deps) > "$work/unsupported.out" 2>&1; then
    echo "FAIL: unsupported version resolved" >&2; exit 1
fi
grep -q 'atlas.version(version = "0.0.1") is not supported' "$work/unsupported.out" || {
    cat "$work/unsupported.out" >&2; echo "FAIL: unsupported version: wrong error" >&2; exit 1; }
echo "PASS: unsupported version fails clearly"

# 4. //... loads.
(cd "$work/untagged" && bazel query @rules_atlas//... >/dev/null)
echo "PASS: @rules_atlas//... loads"
