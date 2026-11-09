"""Bzlmod extension. Single `version` tag class — fetches the Atlas
community-edition CLI for each supported platform.

Same shape as rules_opa: per-platform repos named `atlas_<plat>` each
contain just the binary (`atlas`) plus a tiny BUILD that exposes it as
a filegroup. The toolchain at //toolchain:atlas selects the right one
based on the resolved exec/target platform.
"""

load("//private:repositories.bzl", "atlas_binary_repo")
load("//private:versions.bzl", "ATLAS_VERSIONS", "DEFAULT_VERSION", "PLATFORMS")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _select_version(mctx):
    """The one Atlas version to fetch.

    The extension runs once for the whole build and sees every module's
    tags, but the repos it creates (`atlas_<plat>`) are global, so it
    must pick a single version and create each repo once. The root
    module's `atlas.version()` wins; without one, rules_atlas's own
    (from its MODULE.bazel, which imports these repos and registers the
    toolchain for every consumer — rules_atlas#12); without that,
    DEFAULT_VERSION. Other modules' tags are ignored.
    """
    root = []
    own = []
    for mod in mctx.modules:
        versions = [tag.version for tag in mod.tags.version]
        if mod.is_root:
            root = versions
        elif mod.name == "rules_atlas":
            own = versions
    for candidates, who in [(root, "the root module"), (own, "rules_atlas")]:
        distinct = sorted({v: None for v in candidates}.keys())
        if len(distinct) > 1:
            fail("rules_atlas: {} sets atlas.version() to more than one version ({}); set one.".format(
                who,
                ", ".join(distinct),
            ))
        if distinct:
            return distinct[0]
    return DEFAULT_VERSION

def _impl(mctx):
    version = _select_version(mctx)
    if version not in ATLAS_VERSIONS:
        fail("rules_atlas: atlas.version(version = \"{}\") is not supported. Supported: {}".format(
            version,
            ", ".join(sorted(ATLAS_VERSIONS.keys())),
        ))
    for plat in PLATFORMS.keys():
        atlas_binary_repo(
            name = "atlas_" + plat,
            version = version,
            platform = plat,
        )

atlas = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
