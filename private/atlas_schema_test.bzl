"""atlas_schema_test — Bazel test rule that runs `atlas schema fmt`
in check mode against an Atlas HCL schema file.

Hermetic: no DB needed, just the Atlas CLI + the schema file. The
canonical use case is asserting that schema files in the repo are
fmt-clean (no diff vs. canonical formatting). This catches drift the
same way `gofmt -l` does for Go.

For semantic validation that needs a dev URL (Atlas's `schema
validate` against an actual database engine), use `atlas_schema_test`
with `dev_url = \"sqlite://?mode=memory&_fk=1\"` (default — no
external service required).
"""

def _impl(ctx):
    tc = ctx.toolchains["//toolchain:atlas"]
    atlas_bin = tc.atlas.atlas_bin

    if not ctx.files.srcs:
        fail("atlas_schema_test {}: srcs must be non-empty".format(ctx.label))

    short_paths = [f.short_path for f in ctx.files.srcs]

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{ATLAS_BIN}": atlas_bin.short_path,
            "{INPUTS}": " ".join(["'" + p + "'" for p in short_paths]),
            "{MODE}": ctx.attr.mode,
            "{DEV_URL}": ctx.attr.dev_url,
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [atlas_bin] + ctx.files.srcs)
    return [DefaultInfo(executable = out, runfiles = runfiles)]

atlas_schema_test = rule(
    implementation = _impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".hcl", ".sql"],
            mandatory = True,
            doc = "Atlas schema files (HCL or SQL).",
        ),
        "mode": attr.string(
            default = "fmt",
            values = ["fmt", "validate"],
            doc = "Check mode. `fmt` runs `atlas schema fmt` and asserts " +
                  "the file is fmt-clean (no rewrite). `validate` runs " +
                  "`atlas schema inspect` against `dev_url` to assert the " +
                  "schema parses + resolves against the engine's grammar.",
        ),
        "dev_url": attr.string(
            default = "sqlite://?mode=memory&_fk=1",
            doc = "Atlas dev URL (only consulted in `validate` mode). " +
                  "Default in-memory sqlite keeps the rule fully hermetic; " +
                  "override for engine-specific schemas (e.g. " +
                  "`docker://postgres/16/test`, but that needs Docker).",
        ),
        "_tmpl": attr.label(
            default = "//private:atlas_schema_test.sh.tmpl",
            allow_single_file = True,
        ),
    },
    toolchains = ["//toolchain:atlas"],
)
