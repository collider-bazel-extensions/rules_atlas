# No top-level lint block: only `--env ci` makes data-dependent changes
# errors. An env's lint block replaces the top-level one.
env "ci" {
  # Ignored by atlas_migrate_lint_test: the rule's --dev-url and --dir win.
  dev = "postgres://nobody@127.0.0.1:1/none?sslmode=disable"
  migration {
    dir = "file:///nonexistent"
  }
  lint {
    data_depend {
      error = true
    }
  }
}
