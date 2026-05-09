// Atlas config consumed by the wrapper as
// `atlas migrate diff --config file://atlas.hcl --env local`.
//
// The dev/url values are pulled from $ATLAS_DEV_URL which the
// atlas_migrate_diff_run wrapper exports after the dev_service is
// ready and the env file is sourced.
variable "url" {
  type    = string
  default = getenv("ATLAS_DEV_URL")
}

env "local" {
  src = "file://schema.hcl"
  dev = var.url
  url = var.url
  migration {
    dir = "file://migrations"
  }
}
