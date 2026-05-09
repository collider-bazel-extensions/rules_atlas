"""atlas_operator_install + atlas_operator_install_health_check —
cluster-deploy primitives wrapping rules_kubectl's `kubectl_apply`
over the pinned, pre-rendered Atlas Operator manifest.

Wait shape:
  - Deployment `<namespace>/atlas-operator` Available
  - 2 CRDs: atlasschemas, atlasmigrations (under db.atlasgo.io)

Atlas Operator chart 0.7.29 ships a single Deployment (the manager).
The CRDs ship from the chart's `templates/crds/crd.yaml` so the
combined manifest has them up front; consumers don't need to apply a
separate CRD manifest.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

_OPERATOR_DEPLOY = "atlas-operator"
_OPERATOR_CRDS = [
    "atlasschemas.db.atlasgo.io",
    "atlasmigrations.db.atlasgo.io",
]

def atlas_operator_install(
        name,
        namespace = "atlas-operator-system",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Atlas Operator manifest into `namespace`,
    block until the operator Deployment is Available AND the two
    consumer-facing CRDs are registered.

    Drops into `itest_service.exe`. Wait timeout 300s — chart is small
    (~30MB image).

    Args:
      name: target name.
      namespace: target namespace. Pre-created idempotently. Default
        `atlas-operator-system` matches the rendered manifest's
        Service / Deployment / RBAC namespace selectors. Change at
        your own risk.
      wait_timeout: timeout for the deployment + CRD waits.
      **kwargs: forwarded to `kubectl_apply`.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_atlas//private/manifests:atlas_operator.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = [_OPERATOR_DEPLOY] + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(_OPERATOR_CRDS) + list(extra_crds),
        wait_timeout = wait_timeout,
        **kwargs
    )

def atlas_operator_install_health_check(
        name,
        namespace = "atlas-operator-system",
        **kwargs):
    """Readiness probe paired with `atlas_operator_install`. Same
    wait shape with `--timeout=0s`. Drops into
    `itest_service.health_check`.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = [_OPERATOR_DEPLOY] + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(_OPERATOR_CRDS) + list(extra_crds),
        **kwargs
    )
