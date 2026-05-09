"""Maintainer-only: download + extract the Atlas Operator source
tarball at the sha pinned in tools/versions.bzl. Consumers never
materialize this — the extension is dev_dependency-gated in
MODULE.bazel.

The chart lives at `charts/atlas-operator/` inside the tarball; the
filegroup target globs that subtree for `helm_template`.
"""

load("//tools:versions.bzl", "ATLAS_OPERATOR_VERSIONS")

_BUILD = """\
package(default_visibility = ["//visibility:public"])

# All chart-relevant files (Chart.yaml, values.yaml, templates/**).
filegroup(
    name = "chart_files",
    srcs = glob(["charts/atlas-operator/**/*"]),
)
"""

def _impl(rctx):
    version = rctx.attr.version
    if version not in ATLAS_OPERATOR_VERSIONS:
        fail("rules_atlas: unknown atlas-operator version '{}'. Known: {}".format(
            version, sorted(ATLAS_OPERATOR_VERSIONS.keys()),
        ))
    pin = ATLAS_OPERATOR_VERSIONS[version]
    rctx.download_and_extract(
        url = pin["src_url"],
        sha256 = pin["src_sha256"],
        # Strip the leading `atlas-operator-<ver>/` so paths in the
        # repo are relative to the source root.
        stripPrefix = "atlas-operator-{}".format(version),
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD)

atlas_operator_src_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)
