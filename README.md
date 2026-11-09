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
bazel_dep(name = "rules_atlas", version = "0.5.1")
```

That's all: rules_atlas's own `MODULE.bazel` fetches the Atlas CLI and registers the toolchain. rules_atlas is not in the BCR yet, so pin it (and `rules_kubectl`, below) with `archive_override` or `git_override`.

To choose the Atlas version, set it in your root module:

```python
atlas = use_extension("@rules_atlas//:extensions.bzl", "atlas")
atlas.version(version = "1.2.0")
```

The extension fetches one version for the whole build: the root module's `atlas.version()` if it sets one, otherwise rules_atlas's own (the default, `1.2.0`). Other modules' tags are ignored. Setting two different versions in the root, or a version rules_atlas doesn't pin (`private/versions.bzl`), fails with a message naming `atlas.version`. Before v0.5.1 the root had to set `atlas.version()`, or resolution failed with `does not generate repository "atlas_linux_amd64"` (#12); the extra `use_repo(...)` / `register_toolchains(...)` lines that earlier READMEs asked for are harmless but no longer needed.

The release archive (the tag tarball) leaves out `tests/` and `tools/`, whose packages load dev-only modules, so `bazel query @rules_atlas//...` works for consumers. A `git_override` clone still contains them; name packages instead (for example `@rules_atlas//:all`).

The install primitives also require [`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) ≥ 0.2.0, a transitive dependency: the macros are thin wrappers around `kubectl_apply`. Pin it in your root module too, because rules_atlas's own `git_override` for it applies only when rules_atlas is the root.

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

# Lint the latest migration for destructive changes (sqlite default).
atlas_migrate_lint_test(
    name = "migrations_lint_test",
    migrations = glob(["migrations/*.sql"]),
    # Default latest_n=1 matches the typical PR-gate use case. Set to
    # 0 to lint the entire dir.
)

# Lint postgres-flavored migrations against a rules_pg-backed dev URL.
# JSONB / gen_random_uuid() / etc. don't parse under sqlite; point at
# pg_server instead.
atlas_migrate_lint_test(
    name = "migrations_lint_pg_test",
    migrations = glob(["migrations/*.sql"]),
    dev_service = ":dev_pg",   # rules_pg pg_server
    # dev_url_template defaults to the keys rules_pg writes
    # (PGUSER/PGPASSWORD/PGHOST/PGPORT/PGDATABASE).
    tags = ["requires-postgres"],
)
```

**Any lint diagnostic fails `atlas_migrate_lint_test`**, whatever its
severity. Atlas itself exits non-zero only for errors (destructive changes
such as `DS102`); warnings such as data-dependent changes (`MF101`, `MF103`)
print with exit 0. The test prints one line per diagnostic:

```
20260102000000_email.sql: MF103: Adding a non-nullable "text" column "email" will fail in case table "users" is not empty
```

To accept one, add an [`atlas:nolint`](https://atlasgo.io/lint/analyzers)
directive above the statement in the migration file:

```sql
-- atlas:nolint MF103
ALTER TABLE users ADD COLUMN email text NOT NULL;
```

(Before v0.4.0, warnings passed silently.)

**Project config (v0.5.0).** `config` passes your `atlas.hcl` as `--config` and `env` selects an env, so its `lint {}` block applies in `bazel test` as on a developer's machine:

```python
atlas_migrate_lint_test(
    name = "migrations_lint_test",
    migrations = glob(["migrations/*.sql"]),
    config = "atlas.hcl",
    env = "ci",                 # optional
    fail_on_warnings = False,   # let the lint block's error levels decide
)
```

- **Severity, not visibility.** A `lint {}` block sets analyzer error levels. For example, `data_depend { error = true }` makes `MF103` an error, and `destructive { error = false }` makes `DS102` a warning. Atlas prints the diagnostic either way. So with the default `fail_on_warnings = True`, any diagnostic still fails the test, and the config only matters with `fail_on_warnings = False`, where atlas's verdict stands and warnings are printed.
- **Env vs top-level `lint`.** An env's own `lint {}` block *replaces* the top-level one; the two aren't merged.
- **The rule's flags win.** `--dir`, `--dev-url` (from `dev_url` / `dev_service`) and `--latest` always come from the rule, overriding the env's `migration { dir }`, `dev` and `latest`.
- **Relative paths** inside `atlas.hcl` resolve against the working directory, which is the runfiles root (the workspace root), not the file's own directory. List files the config reads in `data`. `getenv()` sees the test's environment (`env` / `--test_env`).
- **Atlas ignores unknown keys** in a `lint {}` block, so a typo like `errr = true` silently has no effect.
- **The community build** has the core analyzers (destructive, data-dependent, backward-incompatible). `naming` and other Pro analyzers do nothing in it.

**Empty migration sets (v0.5.0).** An empty `migrations` list is an error, unless `allow_empty = True`. Then the test passes and says no migrations were linted, so a lint target can exist before a directory's first migration. Bazel refuses an empty `glob` by default, so use `glob(["tenant_migrations/*.sql"], allow_empty = True)`.

| `atlas_migrate_lint_test` attribute | Default | |
|---|---|---|
| `migrations` | | `*.sql` files in one directory |
| `dev_url` / `dev_service` / `dev_url_template` | sqlite in memory | the dev database (above) |
| `latest_n` | `1` | trailing migrations to lint; `0` = all |
| `config` | none | an `atlas.hcl` (`--config`) |
| `env` | none | an env in `config` (`--env`) |
| `fail_on_warnings` | `True` | `False`: only diagnostics atlas rates as errors fail |
| `allow_empty` | `False` | pass, with a note, when `migrations` is empty |
| `data` | `[]` | files `config` reads |

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

The wrapper launches `pg_server` in the background, polls for its env file, expands the URL template (`${VAR}` / `$VAR` from the env file; pure bash, no `eval`), exports `$ATLAS_DEV_URL`, `cd`s to `$BUILD_WORKING_DIRECTORY`, and exec's `atlas migrate diff --config file://atlas.hcl --env local initial`. Atlas writes a fresh migration file into the directory specified by `migration { dir = ... }` in `atlas.hcl`.

**dev_service contract:** any executable target that, when launched with `RULES_PG_OUTPUT_ENV_FILE` honored (or fallback path `${TEST_TMPDIR:-/tmp}/<name>.env`), writes `KEY=VALUE` lines to that path once ready. `rules_pg`'s `pg_server` is the canonical implementation.

**No host `envsubst` needed** (since v0.4.0): the wrappers expand the template with a bash function, `private/envsubst.bash`, instead of gettext's `envsubst`.

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
