"""atlas_toolchain — exposes the platform-resolved Atlas binary as a
`ToolchainInfo` so consumer rules can resolve it via `ctx.toolchains[...]`
without depending on the binary's specific path.
"""

load("//private:providers.bzl", "AtlasInfo")

ATLAS_TOOLCHAIN_TYPE = Label("//toolchain:atlas")

def _toolchain_impl(ctx):
    info = AtlasInfo(
        version = ctx.attr.version,
        atlas_bin = ctx.file.atlas_bin,
    )
    return [
        platform_common.ToolchainInfo(atlas = info),
        DefaultInfo(
            files = depset([ctx.file.atlas_bin]),
            runfiles = ctx.runfiles(files = [ctx.file.atlas_bin]),
        ),
    ]

atlas_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "atlas_bin": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The platform-specific Atlas executable.",
        ),
    },
)
