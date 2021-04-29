resource "google_container_cluster" "cluster" {
  provider = google-beta

  name                        = "cluster"
  location                    = var.zone
  project                     = google_project.gke_cluster.project_id
  network                     = google_compute_network.vpc_network.self_link
  subnetwork                  = google_compute_subnetwork.vpc_sub_network.self_link
  initial_node_count          = 1
  remove_default_node_pool    = true
  enable_intranode_visibility = true
  enable_legacy_abac          = false
  enable_shielded_nodes       = true
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/21"
    services_ipv4_cidr_block = "/22"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.0.0.0/28"
    master_global_access_config {
      enabled = false
    }
  }

  default_snat_status {
    disabled = true
  }
  cluster_telemetry {
    type = "DISABLED"
  }

  master_auth {
    password = ""
    username = ""
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  release_channel {
    channel = "STABLE"
  }

  network_policy {
    enabled = true
  }

  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }

  addons_config {
    http_load_balancing {
      disabled = true
    }

    network_policy_config {
      disabled = false
    }

    dns_cache_config {
      enabled = true
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

  }
  depends_on = [
    google_project_service.gke_cluster_container
  ]
}

resource "google_container_node_pool" "node_pool" {
  provider = google-beta

  name               = "node-pool"
  location           = var.zone
  project            = google_project.gke_cluster.project_id
  cluster            = google_container_cluster.cluster.name
  max_pods_per_node  = 32
  initial_node_count = 1

  autoscaling {
    min_node_count = 0
    max_node_count = 1
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  node_config {
    preemptible  = true
    machine_type = "n2-highmem-4"
    image_type   = "cos_containerd"
    disk_size_gb = "60"
    disk_type    = "pd-ssd"

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      node_metadata = "SECURE"
    }

    # The metadata key/value pairs assigned to instances in the cluster.
    metadata = {
      # https://cloud.google.com/kubernetes-engine/docs/how-to/protecting-cluster-metadata
      disable-legacy-endpoints = "true"
    }
  }

}

resource "local_file" "k8s_cluster_kubeconfig" {
  sensitive_content = <<EOT
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${google_container_cluster.cluster.master_auth.0.cluster_ca_certificate}
    server: https://${google_container_cluster.cluster.endpoint}
  name: ${google_container_cluster.cluster.name}
contexts:
- context:
    cluster: ${google_container_cluster.cluster.name}
    user: admin-${google_container_cluster.cluster.name}
  name: ${google_container_cluster.cluster.name}
current-context: ${google_container_cluster.cluster.name}
kind: Config
preferences: {}
users:
- name: admin-${google_container_cluster.cluster.name}
  user:
    auth-provider:
      config:
        cmd-args: config config-helper --format=json
        cmd-path: gcloud
        expiry-key: '{.credential.token_expiry}'
        token-key: '{.credential.access_token}'
      name: gcp
EOT
  filename          = "${path.root}/kubeconfig_${google_container_cluster.cluster.name}"
}

output "cluster" {
  value = {
    "kubeconfig" = local_file.k8s_cluster_kubeconfig.filename
  }
}
