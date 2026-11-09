# rules_atlas — design notes

## Two-family-in-one-repo shape

Atlas's value-add is the schema-as-code workflow. Separating CLI from operator into two rule sets would force consumers picking either branch to learn two install patterns later — same conclusion rules_crossplane reached (CLI `crossplane_render_test` + cluster `crossplane_install` in one repo). Both families share the version-pin format (`tools/versions.bzl`) and the binary-toolchain plumbing.

## CLI: community edition, not Atlas Pro

`release.ariga.io/atlas/atlas-{linux,darwin}-{amd64,arm64}-v<ver>` ships the **EULA-licensed** Atlas Pro builds by default. The `atlas-community-*` siblings are Apache-2.0 — strictly the OSS feature set. We pin community to match the family's open-source posture.

Operational difference: the community build is dialect-strict. `atlas schema inspect --dev-url sqlite://...` against a postgres-typed HCL (e.g. `type = serial`) errors with "Unknown column.type". For consumers who need cross-engine validation, override `dev_url` to a `docker://postgres/16/test` URL — but that requires Docker on the runner.

## No update checks from the CLI wrappers

Every wrapper (`atlas_schema_test`, `atlas_migrate_lint_test`,
`atlas_migrate_diff_run`) exports `ATLAS_NO_UPDATE_NOTIFIER=1` and
`ATLAS_NO_UPGRADE_SUGGESTIONS=1`. Otherwise Atlas calls
`vercheck.ariga.io` on each run, a network dependency in a test, and once a
newer Atlas ships it prints an upgrade/deprecation notice to stderr.
`atlas_migrate_lint_test` fails on any output from `atlas migrate lint`,
so the notice failed clean lints as soon as Atlas 1.3.0 was released.

## Install: render-from-source, not OCI

Atlas Operator's official install path is the OCI Helm chart `oci://ghcr.io/ariga/charts/atlas-operator`. There's no GitHub release asset (unlike temporal-operator / spicedb-operator).

Rather than wire OCI auth + bearer-token negotiation into the maintainer flow, we download the upstream **source tarball** at the pinned tag (`v0.7.29.tar.gz`), extract the chart from `charts/atlas-operator/`, and render via `rules_helm`'s `helm_template`. Same end-state as the OCI path (the chart contents are identical) without the auth complexity.

## Wait shape

`atlas_operator_install`:
- Deployment `atlas-operator` Available (the chart's helper template names it after the release name when the release name contains the chart name — we pass `release_name = "atlas-operator"`).
- 2 CRDs registered: `atlasschemas.db.atlasgo.io`, `atlasmigrations.db.atlasgo.io`.

The chart bundles its own CRDs under `templates/crds/crd.yaml` (rendered with `--include-crds`); consumers don't need a separate CRD apply step.

## Smoke composition

5-link itest dep chain:

```
kind_svc → cnpg_install_svc → atlas_install_svc → smoke_test
```

(rules_cloudnativepg already provides `cloudnativepg_install` — this repo composes it as the postgres backing rather than rolling its own. Cross-rule compose pattern, mirroring rules_zitadel v0.3.)

`smoke_test`:
1. Apply Namespace + Secret + CNPG `Cluster` + `AtlasSchema` CR (single yaml).
2. Wait CNPG `.status.phase == "Cluster in healthy state"` AND `readyInstances >= 1`.
3. Wait AtlasSchema `.status.conditions[?(@.type=="Ready")].status == "True"`.
4. `kubectl exec smoke-pg-1 -c postgres -- psql -U app -d app -c "\d users"` and assert `id` + `name` columns are present.

Steps 1–3 confirm the install + reconciliation. Step 4 confirms the schema *actually landed in the database* — without it the smoke would only assert the operator's own status reports, not the value-add (per the family's smoke-test depth rule).

## `atlas_migrate_diff_run` (v0.2)

A `*_run` rule, NOT a `*_test` rule. `migrate diff` is a developer-time interactive command — the consumer needs to inspect the generated migration file, tweak it, commit it. Test rules' isolation model assumes a one-shot exit, which doesn't fit; a regular executable does.

### dev_service contract

Anything whose `DefaultInfo.executable`, when launched with `${TEST_TMPDIR:-/tmp}/<target-name>.env` as the convention path (or with an explicit `RULES_PG_OUTPUT_ENV_FILE` override), writes `KEY=VALUE` lines to that path once the server is ready.

`rules_pg`'s `pg_server` is the canonical implementation. The contract is intentionally minimal so any future MySQL / SQLite / etc. dev-server wrapper can drop in.

### `TEST_TMPDIR` override

`pg_server`'s wrapper unconditionally exports `RULES_PG_OUTPUT_ENV_FILE="${TEST_TMPDIR:-/tmp}/<name>.env"` — handing the launcher our own value via env directly would be a no-op. The wrapper sets `TEST_TMPDIR=<our state dir>` instead, which routes `rules_pg`'s env file into a location we control + clean up.

### URL template expansion: pure-bash `envsubst`

`dev_url_template` defaults to `postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?sslmode=disable` (matches the keys `rules_pg` writes). After sourcing the env file, the wrapper expands the template with `envsubst` from `private/envsubst.bash` (a runfile of both rules) rather than `eval` — autogenerated postgres passwords can contain shell metacharacters that would break naive eval.

Through v0.3.0 this was gettext's `envsubst` from the host PATH, an undeclared host dependency (rules_atlas#6). The bash function matches gettext's no-argument behaviour: `${NAME}` and `$NAME` become the variable's value (empty when unset), values are copied verbatim and not re-expanded, and a `$` not followed by a name stays literal. `//tests:envsubst_test` runs it with `PATH` emptied.

### Substitution markers: `__KEY__`, not `{KEY}`

The wrapper template is bash, full of `${VAR}` expansions. If we use `{KEY}` as the substitution marker, `${KEY_INSIDE_BASH_VAR}` patterns get half-substituted (the inner `{KEY...}` matches a substitution key) and the resulting script is broken. Use `__KEY__` so substitution markers can't collide with bash syntax.

## `atlas_migrate_lint_test` — sqlite vs `dev_service` (v0.3)

`migrate lint` parses each migration's SQL against the dev URL's grammar. The default `dev_url = sqlite://?mode=memory&_fk=1` keeps the rule fully hermetic, but it's dialect-strict — postgres-typed migrations (`JSONB`, `gen_random_uuid()`, `TIMESTAMPTZ`, `::regclass` casts, etc.) reject as "syntax error" against sqlite even though they're valid Postgres.

v0.3 adds an optional `dev_service` attribute (label, executable target) + `dev_url_template` (string) that mirrors `atlas_migrate_diff_run`'s shape. When `dev_service` is set, the wrapper:

1. Launches `dev_service` in the background (`TEST_TMPDIR=<state-dir>` so `rules_pg`'s `pg_server` writes its env file under our control).
2. Polls for `<state-dir>/<dev_service.name>.env` (60s deadline).
3. Sources the env file, expands `dev_url_template` with `private/envsubst.bash`.
4. Passes that URL as `--dev-url` to `atlas migrate lint`.

The dev_service plumbing is the same primitive `atlas_migrate_diff_run` uses (down to the `__KEY__`-marker convention and the `TEST_TMPDIR` override). Eventually a shared internal helper would dedupe the two templates; for now they're parallel, which keeps each rule's wrapper readable end-to-end.

## `atlas_migrate_lint_test` fails on every diagnostic (v0.4)

`atlas migrate lint` exits 1 only for diagnostics its analyzers rate as
errors (destructive changes, `DS1xx`). Warnings, such as data-dependent
changes (`MF101` unique index on existing data, `MF103` non-nullable column
without default), print to **stdout** with exit 0. Through v0.3.0 the
wrapper failed on a non-zero exit or on stderr output, so warnings passed
silently (rules_atlas#6).

The wrapper now runs lint with a `--format` template that prints only the
diagnostics (`<file>: <code>: <text>`, plus suggested fixes and per-file
errors) and fails on a non-zero exit or on any output. A clean lint prints
nothing under that template.

Configuration is Atlas's own: an `-- atlas:nolint [CODE ...]` directive
above a statement suppresses its diagnostics. That keeps each exception
next to the SQL it excuses and reviewable in the PR, which a rule attribute
(e.g. a list of ignored codes) would not. `//tests:lint_warning_fails_test`,
`//tests:lint_destructive_fails_test` and `//tests:lint_nolint_test` cover
the three cases.

## Project config: `config`, `env`, `fail_on_warnings` (v0.5)

rules_atlas#10 asked for the project's `atlas.hcl` lint block to apply at build time. These were checked against atlas community v1.2.0:

- **What a `lint {}` block changes.** Analyzer error levels, i.e. atlas's exit code: `data_depend { error = true }` turns MF103 into exit 1, and `destructive { error = false }` turns DS102 into exit 0. The diagnostic is printed either way. Since v0.4 the wrapper fails on any diagnostic, so error levels alone change nothing. Hence `fail_on_warnings = False`, which makes atlas's exit code, and so the lint block, the verdict. The default stays `True`, so v0.4 behaviour is unchanged.
- **Flags vs env.** `--dev-url`, `--dir` and `--latest` given on the command line override an env's `dev`, `migration { dir }` and `latest`. Tested with an env whose `dev` and `dir` point nowhere; the rule's flags were used. The rule always passes all three, so only the env's `lint` block (and anything else the rule doesn't set) comes from the config.
- **Env lint replaces top-level lint.** With `--env`, an env-level `lint {}` block replaces the top-level one rather than merging with it.
- **Relative paths.** A relative `file://migrations` in an env resolves against the working directory, not the hcl file's directory. Under `bazel test` that's the runfiles root.
- **Unknown keys.** Atlas silently ignores unknown keys in a lint block (`errr = true`). `naming` (Pro) does nothing in the community build.

`//tests:lint_config_*` cover each case: strict (MF103 fails), lenient (DS102 passes), lenient with the default `fail_on_warnings` (fails), and an env's lint block applying only with `env`. Removing `--config` from the wrapper fails exactly the three tests that depend on it; this was checked by hand.

**Empty sets.** An empty `migrations` list is an analysis error that names `allow_empty`. With `allow_empty = True`, the rule emits a script that passes and says no migrations were linted. It doesn't launch `dev_service` or run atlas: there is nothing to lint, and atlas needs a directory.

## One Atlas version per build; no root tag needed (v0.5.1)

The `atlas` extension runs once for the whole build and sees every module's `atlas.version()` tags, but the `atlas_<plat>` repos it creates are global to the extension, so it picks one version and creates each repo once: the root module's tag, else rules_atlas's own (in its `MODULE.bazel`), else `DEFAULT_VERSION` (`private/versions.bzl`). Other modules' tags are ignored.

Through v0.5.0 the extension honoured only the root's tags (`if not mod.is_root: continue`), on the theory that the library's and the consumer's tags would otherwise collide. They don't: the only collision was the extension itself creating a repo twice, which a root with two `atlas.version()` lines still triggered. Meanwhile rules_atlas's own `MODULE.bazel` imports the repos and registers the toolchain for every consumer, so a root without a tag failed to resolve (`does not generate repository "atlas_linux_amd64"`, #12). Two different versions in one module, or one not in `ATLAS_VERSIONS`, now fail with a message naming `atlas.version`.

`toolchain/BUILD.bazel` still states `version = "1.2.0"` on each `atlas_toolchain`; with a single pinned version that matches, but adding a second version to `ATLAS_VERSIONS` needs the toolchain version to follow the selected one.

CI's `consumer` job (`.github/consumer/check.sh`) runs rules_atlas as a dependency from the commit's `git archive`: an untagged root resolves and runs an `atlas_schema_test` at the default version, a repeated identical tag resolves, an unsupported version fails clearly, and `@rules_atlas//...` loads.

## Release archive contents (v0.5.1)

`tests/` and `tools/` are `export-ignore` (`.gitattributes`). Their packages load dev-only modules (`rules_itest`, `rules_kind`, `rules_helm`, `rules_pg`, `rules_cloudnativepg`), which made `@rules_atlas//...` unloadable for consumers. `REPO.bazel` `ignore_directories` would also hide them from this repo's own `bazel test`, so it isn't used. `MODULE.bazel`'s dev-only `use_extension("//tools:extensions.bzl", ...)` is skipped for a non-root module, so the missing `tools/` doesn't matter there. A `git_override` clone still contains both directories.

## What this repo does not (yet) do

- **`AtlasMigration` CR**: same operator handles versioned migrations (the second consumer-facing CRD). Consumers can apply the CR directly while the install macro waits on the same CRDs.
- **`atlas_schema_apply`**: a Bazel-shaped macro that `kubectl apply`s an `AtlasSchema` CR. Possible v0.3 — the question is whether to also expose `atlas_migrate_apply` in the same shape (matrix of two rules × two CRDs).
- **Multi-version operator**: the family's standard pattern (rules_cloudnativepg, rules_kind, rules_helm) is to support N versions side-by-side. Atlas Operator only ships ~one stable version at a time so a single pin is fine.
