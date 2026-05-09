"""atlas_migrate_diff_run — runnable rule that drives `atlas migrate
diff` against a hermetic dev URL provided by a long-running
dev_service target (typically `rules_pg`'s `pg_server`).

Generates a sh_binary-shaped wrapper. Under `bazel run`:

  1. mktemp -d for state (dev_service env file, server PID file).
  2. Launch dev_service in the background; trap kill on exit.
  3. Poll for `<state-dir>/<dev_service.name>.env` (the convention
     `rules_pg`'s `pg_server` follows when handed
     `RULES_PG_OUTPUT_ENV_FILE`).
  4. Source the env file. Expand `dev_url_template` via `envsubst`
     against the now-set env vars; export as `ATLAS_DEV_URL`.
  5. cd into `BUILD_WORKING_DIRECTORY` (the user's invocation cwd
     under `bazel run`; falls back to PWD).
  6. exec `atlas migrate diff --config file://<config> --env <env>`
     with any passthrough args.

`migrate diff` is a developer-time operation — the consumer needs
to inspect the generated migration file, tweak it, commit it. So
this is a `*_run` rule (regular executable), NOT a `*_test` rule.

Compatible with any dev_service whose executable, when handed
`RULES_PG_OUTPUT_ENV_FILE` via env, writes `KEY=VALUE` lines to
that path once the server is ready. `rules_pg`'s `pg_server`
follows this convention; other DB engines (mysql, mariadb) need a
matching server target. The rule itself is engine-agnostic — the
parameterization point is `dev_url_template`.
"""

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:atlas"]
    atlas_bin = tc.atlas.atlas_bin

    dev_service_executable = ctx.executable.dev_service
    dev_service_name = ctx.attr.dev_service.label.name

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    # Use __KEY__ markers (not {KEY}) so substitution doesn't collide
    # with bash `${VAR}` expansion inside the template body.
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "__ATLAS_BIN__": atlas_bin.short_path,
            "__DEV_SERVICE__": dev_service_executable.short_path,
            "__DEV_SERVICE_NAME__": dev_service_name,
            "__DEV_URL_TEMPLATE__": ctx.attr.dev_url_template,
            "__ATLAS_CONFIG__": ctx.file.atlas_config.short_path,
            "__ATLAS_ENV__": ctx.attr.env,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            atlas_bin,
            ctx.file.atlas_config,
        ] + ctx.files.migrations,
    )
    runfiles = runfiles.merge(ctx.attr.dev_service[DefaultInfo].default_runfiles)

    return [DefaultInfo(executable = out, runfiles = runfiles)]

atlas_migrate_diff_run = rule(
    implementation = _impl,
    executable = True,
    attrs = {
        "atlas_config": attr.label(
            allow_single_file = [".hcl"],
            mandatory = True,
            doc = "Atlas config file (typically `atlas.hcl`). Read by " +
                  "`atlas migrate diff --config file://<path> --env <env>`.",
        ),
        "migrations": attr.label_list(
            allow_files = True,
            doc = "Migration files staged into the wrapper's runfiles. " +
                  "Atlas reads/writes the migration directory specified " +
                  "by the `migration { dir = ... }` block in atlas.hcl; " +
                  "the path is relative to BUILD_WORKING_DIRECTORY at " +
                  "invocation time.",
        ),
        "dev_service": attr.label(
            executable = True,
            cfg = "target",
            mandatory = True,
            doc = "Long-running dev-DB service target. Must, when its " +
                  "executable is launched with `RULES_PG_OUTPUT_ENV_FILE` " +
                  "set, write `KEY=VALUE` lines to that path once ready. " +
                  "`rules_pg`'s `pg_server` is the canonical implementation.",
        ),
        "dev_url_template": attr.string(
            default = "postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?sslmode=disable",
            doc = "Atlas dev URL with `${VAR}` placeholders. Expanded via " +
                  "`envsubst` against the env file's contents after the " +
                  "dev_service writes it. Default matches the keys " +
                  "`rules_pg`'s `pg_server` writes (PGHOST/PGPORT/" +
                  "PGDATABASE/PGUSER/PGPASSWORD).",
        ),
        "env": attr.string(
            default = "local",
            doc = "Atlas env section name (`atlas migrate diff --env <env>`).",
        ),
        "_tmpl": attr.label(
            default = "//private:atlas_migrate_diff_run.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:atlas"],
)
