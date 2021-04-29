resource "google_compute_network" "vpc_network" {
  provider = google-beta

  name                    = "vpc-network"
  project                 = google_project.gke_cluster.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}


resource "google_compute_subnetwork" "vpc_sub_network" {
  provider = google-beta

  network = google_compute_network.vpc_network.self_link

  region                   = replace(var.region, "/-[a-d]$/", "")
  name                     = "sub-network"
  project                  = google_project.gke_cluster.project_id
  ip_cidr_range            = "172.16.0.0/20"
  private_ip_google_access = true
}


resource "google_compute_router" "router" {
  provider = google-beta

  name    = "router"
  region  = google_compute_subnetwork.vpc_sub_network.region
  project = google_project.gke_cluster.project_id
  network = google_compute_network.vpc_network.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat" {
  provider = google-beta

  name                               = "router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  project                            = google_project.gke_cluster.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_dns_managed_zone" "dns_zone" {
  provider = google-beta
  project  = google_project.gke_cluster.project_id

  name       = "dns"
  dns_name   = var.dns_name
  visibility = "public"


  depends_on = [
    google_project_service.gke_cluster_dns
  ]
}

data "google_dns_managed_zone" "parent_zone" {
  provider = google-beta

  name    = var.parent_zone
  project = var.parent_zone_project
}

resource "google_dns_record_set" "delegate_child_zone" {
  provider     = google-beta
  managed_zone = data.google_dns_managed_zone.parent_zone.name
  project      = var.parent_zone_project

  name    = google_dns_managed_zone.dns_zone.dns_name
  type    = "NS"
  rrdatas = google_dns_managed_zone.dns_zone.name_servers
}



output "dns" {
  value = {
    "dns_name"     = google_dns_managed_zone.dns_zone.dns_name
    "name_servers" = google_dns_managed_zone.dns_zone.name_servers
  }
}
