"""Atlas CLI binary pins.

Atlas community-edition (Apache-2.0) is downloaded from
release.ariga.io as raw executables (NO tarball wrapper). Default
release.ariga.io binaries (without the `community-` prefix) are
EULA-licensed Atlas Pro builds; the community edition matches
the family's open-source posture.

URL pattern:
    https://release.ariga.io/atlas/atlas-community-<plat>-v<version>

SHA256 sums are published as sibling `.sha256` files.

Maintainer flow:
    bash tools/update_versions.sh <version>
"""

ATLAS_VERSIONS = {
    "1.2.0": {
        "linux_amd64": {
            "url": "https://release.ariga.io/atlas/atlas-community-linux-amd64-v1.2.0",
            "sha256": "19a1f09eaa5469011d2cfb07cd8bdcaa5bb39fbf7c31bd63a60ba9d9aa7f562d",
        },
        "linux_arm64": {
            "url": "https://release.ariga.io/atlas/atlas-community-linux-arm64-v1.2.0",
            "sha256": "8f7f89dd977a85ffe9be66fe157ce462a03036ef67a229ce8a39c3b1856e53f9",
        },
        "darwin_amd64": {
            "url": "https://release.ariga.io/atlas/atlas-community-darwin-amd64-v1.2.0",
            "sha256": "9c086c6b89f99fcbe74bf58a3d5159c0a743735abb3e6fa91e05988524c3444d",
        },
        "darwin_arm64": {
            "url": "https://release.ariga.io/atlas/atlas-community-darwin-arm64-v1.2.0",
            "sha256": "6acefeafa2e657af4d59432a52b8c13d76033f5b8f5fd4abd09a224d2d9b8a6d",
        },
    },
}

PLATFORMS = {
    "linux_amd64":  ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "linux_arm64":  ["@platforms//os:linux", "@platforms//cpu:arm64"],
    "darwin_amd64": ["@platforms//os:osx",   "@platforms//cpu:x86_64"],
    "darwin_arm64": ["@platforms//os:osx",   "@platforms//cpu:arm64"],
}
