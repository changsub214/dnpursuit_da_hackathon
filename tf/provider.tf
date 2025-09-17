terraform {
  required_providers {
    google = {
      version = "~> 5.10"
    }
  }
}

provider "google" {
    project = var.gcp_project_id
    region  = var.gcp_region
    zone = var.gcp_zone
}