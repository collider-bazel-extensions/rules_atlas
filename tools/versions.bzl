"""Maintainer-side: Atlas Operator chart pin for the helm-render flow.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifest at
`//private/manifests:atlas_operator.yaml` is what consumers actually
consume.

Atlas Operator's official install path is an OCI Helm chart at
`oci://ghcr.io/ariga/charts/atlas-operator`. Rather than wire OCI
auth into the maintainer flow, we render against the chart source
inside the upstream GitHub release tarball (`charts/atlas-operator/`
in `ariga/atlas-operator@v<ver>.tar.gz`).

Update flow:
    1. Edit ATLAS_OPERATOR_VERSIONS to add/change the entry, including
       src_url + src_sha256:
           curl -fsL "<url>" | sha256sum
    2. Add a `helm_template` + `sh_binary` block in tools/BUILD.bazel
       for the new version.
    3. `bash tools/render_atlas_operator.sh <version>`.
"""

ATLAS_OPERATOR_VERSIONS = {
    "0.7.29": {
        "src_url":    "https://github.com/ariga/atlas-operator/archive/refs/tags/v0.7.29.tar.gz",
        "src_sha256": "970c6c524231a806f13f1b50cdf14437a66ebe148846edb8e7e2bbfed65169a4",
        # Path to the chart directory inside the extracted tarball.
        # The tarball strip-prefixes everything under
        # `atlas-operator-<ver>/`; the chart lives at
        # `charts/atlas-operator/`.
        "chart_subdir": "charts/atlas-operator",
    },
}
