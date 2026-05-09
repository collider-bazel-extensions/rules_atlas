"""atlas_migrate_lint — Bazel test rule that runs `atlas migrate lint`
over a versioned-migrations directory.

`migrate lint` checks each migration file against a set of static
analysis rules (destructive changes, data-loss-risk, missing
backward-compat shims, etc). Atlas needs a `--dev-url` for the
engine grammar; default is in-memory sqlite for fully hermetic
operation. Override for engine-specific dialects.

The rule passes the migrations directory as `--dir file://<dir>` and
runs against the *latest* migration (`--latest 1`) by default, since
the typical CI gate is "did the last commit introduce a destructive
change?" Override `latest_n` for fuller scope.
"""

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:atlas"]
    atlas_bin = tc.atlas.atlas_bin

    if not ctx.files.migrations:
        fail("atlas_migrate_lint {}: migrations must be non-empty".format(ctx.label))

    # All migrations files share a common parent directory (validated
    # at runtime by `atlas migrate lint`). Pass each file's
    # short_path; the wrapper picks the dirname of any one to feed
    # `--dir file://...`.
    short_paths = [f.short_path for f in ctx.files.migrations]

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{ATLAS_BIN}": atlas_bin.short_path,
            "{INPUTS}": " ".join(["'" + p + "'" for p in short_paths]),
            "{DEV_URL}": ctx.attr.dev_url,
            "{LATEST_N}": str(ctx.attr.latest_n),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [atlas_bin] + ctx.files.migrations)
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
            doc = "Atlas dev URL for grammar resolution. Default sqlite " +
                  "in-memory keeps the rule fully hermetic.",
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

