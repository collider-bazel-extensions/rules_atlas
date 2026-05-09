-- Postgres-flavored migration. Uses `gen_random_uuid()` (pgcrypto /
-- builtin in PG 13+) and `JSONB` — both reject under sqlite. Proves
-- atlas_migrate_lint_test's dev_service path validates against a
-- real Postgres rather than the sqlite default.
CREATE TABLE events (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payload   JSONB NOT NULL,
    occurred  TIMESTAMPTZ NOT NULL DEFAULT now()
);
