"""Bzlmod extension. Single `version` tag class — fetches the Atlas
community-edition CLI for each supported platform.

Same shape as rules_opa: per-platform repos named `atlas_<plat>` each
contain just the binary (`atlas`) plus a tiny BUILD that exposes it as
a filegroup. The toolchain at //toolchain:atlas selects the right one
based on the resolved exec/target platform.
"""

load("//private:repositories.bzl", "atlas_binary_repo")
load("//private:versions.bzl", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    # Only honor `version` tags from the root module. Without this guard,
    # both rules_atlas (when consumed as a dep) and the consumer would
    # each emit `@atlas_<plat>` repos and Bazel would collide them. The
    # library's own MODULE.bazel still needs `atlas.version(...)` so its
    # in-tree tests can build, but that only fires when rules_atlas
    # itself is the root.
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            for plat in PLATFORMS.keys():
                atlas_binary_repo(
                    name = "atlas_" + plat,
                    version = tag.version,
                    platform = plat,
                )

atlas = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
