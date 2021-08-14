terraform {
  backend "gcs" {
    bucket = "hugall8-terraform-state"
    prefix = "terraform/forest"
  }
}