# rules_atlas

Bazel rules for [Atlas](https://atlasgo.io) — declarative database schema management. Two families in one repo:

- **CLI primitives** — hermetic Atlas binary as Bazel rules:
  - `atlas_schema_test` — runs `atlas schema fmt --check` (or `atlas schema inspect` against a dev URL) on an HCL/SQL schema file.
  - `atlas_migrate_lint_test` — runs `atlas migrate lint` over a versioned-migrations directory.
  - `atlas_migrate_diff_run` *(v0.2)* — `bazel run`-shaped target that drives `atlas migrate diff` against a dev URL provided by a long-running dev_service (typically [`rules_pg`](https://github.com/collider-bazel-extensions/rules_pg)'s `pg_server`).
- **Install primitives** — Atlas Kubernetes Operator install over `rules_kubectl`:
  - `atlas_operator_install` — applies the pinned Atlas Operator manifest, waits for the operator Deployment + `AtlasSchema`/`AtlasMigration` CRDs.
  - `atlas_operator_install_health_check` — paired readiness probe.

## Install (Bzlmod)

```python
bazel_dep(name = "rules_atlas", version = "0.2.0")
```

If you only need the CLI primitives, that's all the wiring needed — the binary toolchain registers itself via the module extension.

The install primitives also require [`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) ≥ 0.2.0 (transitive — the macros are thin wrappers around `kubectl_apply`).

### Atlas community vs Atlas Pro

The bundled binary is the **Apache-2.0 community edition** (`atlas-community-*` from `release.ariga.io`). The default Atlas binary at `atlasgo.sh` is EULA-licensed (Atlas Pro features baked in). The community build is dialect-strict — postgres-typed schemas (e.g. `serial`) won't validate against a sqlite dev URL — but it's fully OSS and matches this repo's posture.

## CLI primitives

```python
load("@rules_atlas//:defs.bzl", "atlas_schema_test", "atlas_migrate_lint_test")

# fmt-check a schema file. Hermetic — no DB needed.
atlas_schema_test(
    name = "schema_fmt_test",
    srcs = ["schema.hcl"],
)

# Validate a schema against an in-memory sqlite dev URL.
atlas_schema_test(
    name = "schema_validate_test",
    srcs = ["schema.hcl"],
    mode = "validate",
    # Default dev_url is "sqlite://?mode=memory&_fk=1". Override for
    # engine-specific schemas (e.g. "docker://postgres/16/test", which
    # requires Docker on the runner).
)

# Lint the latest migration for destructive changes.
atlas_migrate_lint_test(
    name = "migrations_lint_test",
    migrations = glob(["migrations/*.sql"]),
    # Default latest_n=1 matches the typical PR-gate use case. Set to
    # 0 to lint the entire dir.
)
```

### `atlas_migrate_diff_run` (v0.2)

`bazel run`-shaped — invokes `atlas migrate diff` against a hermetic dev URL provided by a long-running `dev_service` target. Useful for developer-time migration generation:

```python
load("@rules_atlas//:defs.bzl", "atlas_migrate_diff_run")
load("@rules_pg//:defs.bzl", "pg_server", "postgres_schema")

postgres_schema(name = "empty", srcs = [])
pg_server(name = "dev_pg", schema = ":empty")

atlas_migrate_diff_run(
    name = "migrate-diff",
    atlas_config = "atlas.hcl",
    migrations = glob(["migrations/*"]),
    dev_service = ":dev_pg",
    env = "local",
    # Default dev_url_template matches the keys rules_pg writes:
    # "postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?sslmode=disable"
)
```

Then:

```sh
bazel run //pkg/db:migrate-diff -- initial
```

The wrapper launches `pg_server` in the background, polls for its env file, expands the URL template via `envsubst`, exports `$ATLAS_DEV_URL`, `cd`s to `$BUILD_WORKING_DIRECTORY`, and exec's `atlas migrate diff --config file://atlas.hcl --env local initial`. Atlas writes a fresh migration file into the directory specified by `migration { dir = ... }` in `atlas.hcl`.

**dev_service contract:** any executable target that, when launched with `RULES_PG_OUTPUT_ENV_FILE` honored (or fallback path `${TEST_TMPDIR:-/tmp}/<name>.env`), writes `KEY=VALUE` lines to that path once ready. `rules_pg`'s `pg_server` is the canonical implementation.

**Runtime dependency:** `envsubst` (gettext-base on Debian/Ubuntu, preinstalled on GitHub Ubuntu runners).

## Install primitives

`atlas_operator_install` drops directly into `itest_service.exe`. The `Atlas Operator` reconciles `AtlasSchema` and `AtlasMigration` custom resources — apply your CR after the operator is up and the operator drives the schema diff against your target database.

```python
load("@rules_atlas//:defs.bzl", "atlas_operator_install", "atlas_operator_install_health_check")
load("@rules_itest//:itest.bzl", "itest_service")

atlas_operator_install(
    name = "atlas_install_bin",
    tags = ["manual"],
)

atlas_operator_install_health_check(
    name = "atlas_health_bin",
    tags = ["manual"],
)

itest_service(
    name = "atlas_install_svc",
    exe = ":atlas_install_bin",
    health_check = ":atlas_health_bin",
    deps = [":kind_svc"],
    tags = ["manual"],
)
```

The included smoke (`tests/install_smoke/`) composes a [CloudNativePG](https://github.com/collider-bazel-extensions/rules_cloudnativepg)-managed Postgres + this rule + an `AtlasSchema` CR, then `kubectl exec`s `psql` to verify the table actually landed.

## Pinned versions

| Component | Version | Source |
|-----------|---------|--------|
| Atlas CLI (community) | `1.2.0` | https://release.ariga.io/atlas/atlas-community-* |
| Atlas Operator chart | `0.7.29` | `charts/atlas-operator/` in https://github.com/ariga/atlas-operator |

The operator manifest is rendered at maintainer time via `tools/render_atlas_operator.sh <version>` (uses [rules_helm](https://github.com/collider-bazel-extensions/rules_helm); no host helm required) and committed to `private/manifests/atlas_operator.yaml`. Consumers don't pull the source tarball.

## See also

- [DESIGN.md](DESIGN.md) — architecture, design tradeoffs.
- [Atlas docs](https://atlasgo.io/docs)
- [Atlas Operator docs](https://atlasgo.io/integrations/kubernetes/operator)
