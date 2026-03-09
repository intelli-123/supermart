locals {
  service_name = "svc-${var.suffix}-${var.environment}"
}

resource "google_cloud_run_v2_service" "app" {
  project  = var.project_id
  location = var.region
  name     = local.service_name

  template {
    service_account = var.service_account_email

    containers {
      name  = "supermart-api"
      image = var.image

      ports {
        container_port = 8080
      }

      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "docker"
      }

      # Cloud SQL Auth Proxy sidecar listens on 127.0.0.1:3306
      env {
        name  = "SPRING_DATASOURCE_URL"
        value = "jdbc:mysql://127.0.0.1:3306/${var.db_name}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
      }

      env {
        name  = "SPRING_DATASOURCE_USERNAME"
        value = var.db_user
      }

      env {
        name  = "SPRING_DATASOURCE_PASSWORD"
        value = var.db_password
      }

      env {
        name  = "APP_JWT_SECRET"
        value = var.jwt_secret
      }

      env {
        name  = "APP_JWT_ACCESS_TOKEN_EXPIRATION_MS"
        value = "3600000"
      }

      env {
        name  = "APP_JWT_REFRESH_TOKEN_EXPIRATION_MS"
        value = "86400000"
      }

      env {
        name  = "APP_TELEMETRY_RATE_LIMIT_PER_MINUTE"
        value = "60"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      # Wait for the Cloud SQL proxy to be ready before starting the app
      depends_on = ["cloud-sql-proxy"]
    }

    # Cloud SQL Auth Proxy sidecar — handles authenticated connections to Cloud SQL
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2"
      args  = ["--port=3306", var.cloudsql_connection_name]

      # startup_probe is required by Cloud Run when this container is listed in depends_on
      startup_probe {
        tcp_socket {
          port = 3306
        }
        initial_delay_seconds = 5
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      resources {
        limits = {
          cpu    = "0.5"
          memory = "256Mi"
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Allow unauthenticated public access to the API
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
