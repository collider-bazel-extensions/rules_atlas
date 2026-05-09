"""Providers exposed by rules_atlas."""

AtlasInfo = provider(
    doc = "Atlas CLI toolchain info.",
    fields = {
        "version": "string — pinned Atlas version",
        "atlas_bin": "File — the platform-specific Atlas executable",
    },
)
