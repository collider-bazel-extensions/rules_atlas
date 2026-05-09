"""Maintainer-only chart-source fetch — fires only when rules_atlas is
the root module. Consumers don't pull the source tarball.
"""

load("//tools:repositories.bzl", "atlas_operator_src_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            atlas_operator_src_repository(
                name = "atlas_operator_src_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

atlas_operator_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
