data "google_client_config" "default" {
  provider = google-beta
}


provider "kubernetes" {
  host                   = "https://${google_container_cluster.cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
}
resource "kubernetes_namespace" "external_dns_ns" {
  metadata {
    name = "tool-external-dns"

  }

  depends_on = [
    google_container_node_pool.node_pool
  ]
}

resource "kubernetes_secret" "external_dns_secret" {
  metadata {
    namespace = kubernetes_namespace.external_dns_ns.metadata.0.name
    name      = "sa-dns-secret"
  }

  data = {
    "credentials.json" = "${base64decode(google_service_account_key.node_account.private_key)}"
  }

}


provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.cluster.master_auth[0].cluster_ca_certificate)
  }
}

resource "helm_release" "external_dns" {
  name         = "external-dns-tool"
  namespace    = kubernetes_namespace.external_dns_ns.metadata.0.name
  repository   = "https://charts.bitnami.com/bitnami"
  chart        = "external-dns"
  reset_values = true


  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "provider"
    value = "google"
  }
  set_sensitive {
    name  = "google.project"
    value = google_dns_managed_zone.dns_zone.project
  }
  set_sensitive {
    name  = "google.serviceAccountSecret"
    value = kubernetes_secret.external_dns_secret.metadata.0.name
  }
}

resource "helm_release" "ingress_controller" {
  name             = "nginx-ingress-tool"
  namespace        = "tool-nginx-ingress"
  create_namespace = true
  # verify     = true
  repository   = "https://kubernetes.github.io/ingress-nginx"
  chart        = "ingress-nginx"
  reset_values = true

  values = [
    <<EOT
udp:
  7777: "satisfactory/satisfactory-service:7777"
EOT
  ]

  depends_on = [
    google_container_node_pool.node_pool
  ]
  set {
    name  = "controller.service.enableHttps"
    value = false
  }
  set {
    name  = "controller.service.enableHttp"
    value = false
  }

}

resource "kubernetes_namespace" "satisfactory_ns" {
  metadata {
    name = "satisfactory"

  }

  depends_on = [
    google_container_node_pool.node_pool
  ]
}

resource "kubernetes_secret" "pull_secret" {
  metadata {
    name      = "github-pull-secret"
    namespace = kubernetes_namespace.satisfactory_ns.metadata.0.name

  }

  data = {
    ".dockerconfigjson" = <<DOCKER
{
  "auths": {
    "${var.registry_server}": {
      "auth": "${base64encode("${var.registry_username}:${var.registry_password}")}"
    }
  }
}
DOCKER
  }

  type = "kubernetes.io/dockerconfigjson"
}



resource "kubernetes_persistent_volume_claim" "save_pvc" {
  metadata {
    name      = "save-pvc"
    namespace = kubernetes_namespace.satisfactory_ns.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "premium-rwo"
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}


resource "kubernetes_deployment" "satisfactory" {
  metadata {
    name      = "satisfactory-deployment"
    namespace = kubernetes_namespace.satisfactory_ns.metadata.0.name
    labels = {
      app = "satisfactory"
    }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        app = "satisfactory"
      }
    }

    template {
      metadata {
        labels = {
          app = "satisfactory"
        }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret.pull_secret.metadata.0.name
        }

        volume {
          name = "save-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.save_pvc.metadata.0.name
          }
        }
        container {
          image = "${var.registry_server}/${var.image_name}:${var.image_tag}"
          # image_pull_policy = "Always"
          image_pull_policy = "IfNotPresent"

          name  = "main"
          command = [ "bash", "-c" ]  
          # args = [ "sleep 3600" ]
          args = ["set -x && dpkg --add-architecture i386 && apt update && apt install -y tmux python3 ca-certificates winbind libfreetype6 libfreetype6:i386 locales && wine start FactoryGame.exe -nosteamclient -nullrhi -nosplash -nosound && tail -f \"$${GAMECONFIGDIR}/Logs/FactoryGame.log\""]

          volume_mount {
            mount_path="/root/.wine/drive_c/users/root/Local Settings/Application Data/FactoryGame/Saved"
            name = "save-pv"
          }

          resources {
            limits = {
              cpu    = "3"
              memory = "25Gi"
            }
            requests = {
              cpu    = "3"
              memory = "25Gi"
            }
          }


        }
      }
    }
  }
}


resource "kubernetes_service" "satisfactory_service" {
  metadata {
    name      = "satisfactory-service"
    namespace = kubernetes_namespace.satisfactory_ns.metadata.0.name
  }
  spec {
    selector = {
      app = "satisfactory"
    }
    port {
      protocol    = "UDP"
      port        = 7777
      target_port = 7777
    }
  }
}
