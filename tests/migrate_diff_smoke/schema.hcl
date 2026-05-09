// Target schema state. The smoke runs `atlas migrate diff` against
// an empty migrations dir, so this is the full diff Atlas should
// emit as a fresh migration.
schema "public" {}

table "items" {
  schema = schema.public
  column "id" {
    null = false
    type = integer
  }
  column "label" {
    null = false
    type = text
  }
  primary_key {
    columns = [column.id]
  }
}
