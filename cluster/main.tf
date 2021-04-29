variable "project_id" {
  type = string
}
variable "region" {
  type = string
}
variable "zone" {
  type = string
}

variable "billing_name" {
  type = string
}

variable "dns_name" {
  type = string
}

variable "parent_zone" {
  type = string
}

variable "parent_zone_project" {
  type = string
}
variable "registry_server" {
  type = string
}
variable "registry_password" {
  type = string
}
variable "registry_username" {
  type = string
}
variable "image_name" {
  type = string
}
variable "image_tag" {
  type    = string
  default = "latest"
}
terraform {
  backend "gcs" {
    bucket = "terraform-rdp-backend"
    prefix = "terraform/state"
  }
}


provider "google-beta" {
  version = "3.65.0"
  # project = var.project_id
  region = var.region
  zone   = var.zone
}

resource "random_string" "gke_cluster_rnd_uid" {
  length  = 10
  upper   = false
  lower   = true
  number  = true
  special = false
}

data "google_billing_account" "acct" {
  provider     = google-beta
  open         = true
  display_name = var.billing_name
}


resource "google_project" "gke_cluster" {
  provider = google-beta

  name                = var.project_id
  project_id          = random_string.gke_cluster_rnd_uid.result
  auto_create_network = false
  billing_account     = data.google_billing_account.acct.id
}

resource "google_project_service" "gke_cluster_container" {
  provider                   = google-beta
  project                    = google_project.gke_cluster.project_id
  service                    = "container.googleapis.com"
  disable_dependent_services = true
}

resource "google_project_service" "gke_cluster_dns" {
  provider = google-beta


  project                    = google_project.gke_cluster.project_id
  service                    = "dns.googleapis.com"
  disable_dependent_services = true
}



resource "google_service_account" "node_account" {
  provider = google-beta

  account_id   = "node-account"
  display_name = "node-account"
  project      = google_project.gke_cluster.project_id

}

resource "google_service_account_key" "node_account" {
  provider = google-beta

  service_account_id = google_service_account.node_account.name
}

resource "google_project_iam_member" "node_account_dns_admin" {
  provider = google-beta

  project = google_project.gke_cluster.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.node_account.email}"

  depends_on = [
    google_service_account.node_account,
    google_project_service.gke_cluster_dns
  ]
}

output "accounts" {
  value = google_service_account.node_account.email
}
