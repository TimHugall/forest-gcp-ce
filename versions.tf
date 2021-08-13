terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
  required_version = ">= 0.14"
}

provider "google" {
  project = "forest-309522"
  region  = "australia-southeast1"
}

# comment out if not using route 53
provider "aws" {
  region = "ap-southeast-2"
}