"""atlas_migrate_lint_test — Bazel test rule that runs `atlas migrate
lint` over a versioned-migrations directory.

`migrate lint` checks each migration file against a set of static
analysis rules (destructive changes, data-loss-risk, missing
backward-compat shims, etc). Atlas needs a `--dev-url` for the
engine grammar; default is in-memory sqlite for fully hermetic
operation. Override for engine-specific dialects.

Two ways to provide the dev URL:

  1. `dev_url` (string, default `sqlite://?mode=memory&_fk=1`) —
     literal URL passed straight to atlas. Hermetic; works for
     sqlite-flavored migrations.
  2. `dev_service` + `dev_url_template` — point at a long-running
     dev-DB target (typically rules_pg's `pg_server`). The wrapper
     launches it in the background, polls for the convention env
     file at `${TEST_TMPDIR:-/tmp}/<dev_service.name>.env`, expands
     the URL template via `envsubst`, then runs atlas migrate lint
     against that URL. Same mechanism as `atlas_migrate_diff_run`.
     Use this for postgres-flavored migrations (JSONB, gen_random_uuid,
     etc.) that can't lint against sqlite.

The rule passes the migrations directory as `--dir file://<dir>` and
runs against the *latest* migration (`--latest 1`) by default, since
the typical CI gate is "did the last commit introduce a destructive
change?" Override `latest_n` for fuller scope.
"""

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:atlas"]
    atlas_bin = tc.atlas.atlas_bin

    if not ctx.files.migrations:
        fail("atlas_migrate_lint_test {}: migrations must be non-empty".format(ctx.label))

    # All migrations files share a common parent directory (validated
    # at runtime by `atlas migrate lint`). Pass each file's
    # short_path; the wrapper picks the dirname of any one to feed
    # `--dir file://...`.
    short_paths = [f.short_path for f in ctx.files.migrations]

    # `dev_service` takes precedence over `dev_url` when both are set
    # (the latter has a non-empty default). Documented in the attr
    # docstrings.

    # Substitution markers use __KEY__ syntax so they don't collide
    # with bash `${VAR}` expansion in the template body — same lesson
    # we hit while implementing atlas_migrate_diff_run.
    substitutions = {
        "__ATLAS_BIN__": atlas_bin.short_path,
        "__INPUTS__": " ".join(["'" + p + "'" for p in short_paths]),
        "__DEV_URL__": ctx.attr.dev_url,
        "__LATEST_N__": str(ctx.attr.latest_n),
        "__DEV_SERVICE__": "",
        "__DEV_SERVICE_NAME__": "",
        "__DEV_URL_TEMPLATE__": "",
    }

    runfiles_files = [atlas_bin] + ctx.files.migrations

    if ctx.attr.dev_service:
        dev_service_executable = ctx.executable.dev_service
        substitutions["__DEV_SERVICE__"] = dev_service_executable.short_path
        substitutions["__DEV_SERVICE_NAME__"] = ctx.attr.dev_service.label.name
        substitutions["__DEV_URL_TEMPLATE__"] = ctx.attr.dev_url_template

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = substitutions,
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = runfiles_files)
    if ctx.attr.dev_service:
        runfiles = runfiles.merge(ctx.attr.dev_service[DefaultInfo].default_runfiles)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

atlas_migrate_lint_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "migrations": attr.label_list(
            allow_files = [".sql"],
            mandatory = True,
            doc = "Migration files (`*.sql`). All must live in the same " +
                  "directory — the rule passes the dirname to `--dir`.",
        ),
        "dev_url": attr.string(
            default = "sqlite://?mode=memory&_fk=1",
            doc = "Literal Atlas dev URL. Default sqlite in-memory keeps " +
                  "the rule fully hermetic. Ignored when `dev_service` " +
                  "is also set (the dev_service-derived URL takes " +
                  "precedence). To validate postgres-flavored migrations " +
                  "(JSONB, gen_random_uuid, etc.), use `dev_service` " +
                  "instead — sqlite is dialect-strict.",
        ),
        "dev_service": attr.label(
            executable = True,
            cfg = "target",
            doc = "Optional long-running dev-DB service target. When set, " +
                  "the wrapper launches it in the background, polls for " +
                  "`${TEST_TMPDIR:-/tmp}/<name>.env`, expands `dev_url_template` " +
                  "via envsubst, and uses that as the `--dev-url` (overriding " +
                  "any `dev_url` value). `rules_pg`'s `pg_server` is the " +
                  "canonical implementation.",
        ),
        "dev_url_template": attr.string(
            default = "postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?sslmode=disable",
            doc = "URL template with `${VAR}` placeholders, expanded via " +
                  "envsubst against the `dev_service` env file. Default " +
                  "matches the keys `rules_pg`'s `pg_server` writes. " +
                  "Ignored when `dev_service` is unset.",
        ),
        "latest_n": attr.int(
            default = 1,
            doc = "Number of trailing migrations to lint (`--latest N`). " +
                  "Default 1 matches the typical PR-gate use case (\"did " +
                  "this commit add a destructive change?\"); set to 0 to " +
                  "lint the entire dir.",
        ),
        "_tmpl": attr.label(
            default = "//private:atlas_migrate_lint.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:atlas"],
)
