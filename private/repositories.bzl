"""Per-platform binary repo. Downloads the Atlas executable at the
pinned URL + sha256 for one platform.
"""

load(":versions.bzl", "ATLAS_VERSIONS")

_BUILD_TMPL = """\
package(default_visibility = ["//visibility:public"])

# Filegroup name MUST differ from the source file "atlas" — otherwise
# `srcs = ["atlas"]` resolves to the filegroup itself and triggers a
# cycle (same lesson rules_opa learned).
filegroup(
    name = "bin",
    srcs = ["atlas"],
)
"""

def _impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform
    if version not in ATLAS_VERSIONS:
        fail("rules_atlas: unknown version '{}'. Known: {}".format(
            version,
            sorted(ATLAS_VERSIONS.keys()),
        ))
    plats = ATLAS_VERSIONS[version]
    if platform not in plats:
        fail("rules_atlas: version {} has no entry for platform '{}'. Have: {}".format(
            version, platform, sorted(plats.keys()),
        ))
    info = plats[platform]
    rctx.download(
        url = info["url"],
        output = "atlas",
        sha256 = info["sha256"],
        executable = True,
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD_TMPL)

atlas_binary_repo = repository_rule(
    implementation = _impl,
    attrs = {
        "version":  attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
    },
)
