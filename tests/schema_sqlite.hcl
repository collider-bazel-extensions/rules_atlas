schema "main" {
}

table "items" {
  schema = schema.main
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
