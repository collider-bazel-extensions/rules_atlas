"""Public API for rules_atlas.

CLI primitives (no cluster needed):
  atlas_schema_test  — runs `atlas schema fmt` (or `inspect`) over an
                       HCL/SQL schema file.
  atlas_migrate_lint — runs `atlas migrate lint` over a versioned
                       migrations directory.

Install primitives (cluster-deploy via rules_kubectl):
  atlas_operator_install              — applies the pinned Atlas
                                        Operator manifest, waits for
                                        the operator Deployment +
                                        AtlasSchema/AtlasMigration CRDs.
  atlas_operator_install_health_check — paired readiness probe.
"""

load("//private:atlas_migrate_diff_run.bzl", _atlas_migrate_diff_run = "atlas_migrate_diff_run")
load("//private:atlas_migrate_lint.bzl", _atlas_migrate_lint_test = "atlas_migrate_lint_test")
load("//private:atlas_operator_install.bzl",
     _atlas_operator_install = "atlas_operator_install",
     _atlas_operator_install_health_check = "atlas_operator_install_health_check")
load("//private:atlas_schema_test.bzl", _atlas_schema_test = "atlas_schema_test")
load("//private:providers.bzl", _AtlasInfo = "AtlasInfo")

atlas_schema_test = _atlas_schema_test
# Bazel test-rule names must end in `_test` — `atlas_migrate_lint_test`
# is the public surface (the underlying Atlas verb is still
# `atlas migrate lint`).
atlas_migrate_lint_test = _atlas_migrate_lint_test
# Runnable companion to atlas_migrate_lint_test: drives `atlas migrate
# diff` against a hermetic dev URL provided by a long-running
# dev_service (typically rules_pg's pg_server).
atlas_migrate_diff_run = _atlas_migrate_diff_run
atlas_operator_install = _atlas_operator_install
atlas_operator_install_health_check = _atlas_operator_install_health_check

AtlasInfo = _AtlasInfo
