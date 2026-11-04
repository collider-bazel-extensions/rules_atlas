"""Analysis-time tests: atlas_migrate_lint_test's attribute errors."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_atlas//:defs.bzl", "atlas_migrate_lint_test")

def _fails_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_fails_test = analysistest.make(
    _fails_impl,
    expect_failure = True,
    attrs = {"message": attr.string()},
)

def analysis_test_suite(name):
    s = name + "_subject"
    atlas_migrate_lint_test(name = s + "_empty", migrations = [], tags = ["manual"])
    atlas_migrate_lint_test(
        name = s + "_env_without_config",
        migrations = ["migrations/20260101000000_init.sql"],
        env = "ci",
        tags = ["manual"],
    )
    tests = {
        "_empty": (s + "_empty", "Set allow_empty = True"),
        "_env_without_config": (s + "_env_without_config", "needs config"),
    }
    for suffix, (target, message) in tests.items():
        _fails_test(name = name + suffix, target_under_test = ":" + target, message = message)
    native.test_suite(name = name, tests = [":" + name + t for t in tests])
