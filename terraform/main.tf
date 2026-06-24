provider "google" {
  project = var.project_id
  region  = var.region
}

# Fetch project metadata (specifically the project number) to construct the IAP service agent email
data "google_project" "project" {}

# 1. Create a dedicated Service Account for the Cloud Run container
resource "google_service_account" "demo_runner" {
  account_id   = "agy-demo-runner"
  display_name = "Antigravity Demo Runner"
  description  = "Service account for the interactive terminal demo running on Cloud Run"
}

# 2. Grant the Service Account permissions to call Vertex AI (Gemini API)
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.demo_runner.email}"
}

# 3. Grant the Service Account permissions to write logs to Cloud Logging
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.demo_runner.email}"
}

# 4. Deploy the Cloud Run Service with Direct IAP enabled
resource "google_cloud_run_v2_service" "demo_service" {
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL" # Direct IAP will protect all ingress paths, including the default URL

  # CRITICAL: Enable Identity-Aware Proxy directly on the Cloud Run Service
  # This secures the default *.run.app URL without needing a Load Balancer or custom domain.
  iap_enabled = true

  template {
    # CRITICAL: Concurrency = 1 guarantees dedicated container instance per user
    max_instance_request_concurrency = 1
    service_account                  = google_service_account.demo_runner.email
    timeout                          = "3600s" # 1 hour timeout for long running agent sessions

    containers {
      image = var.image_uri

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2.0" # 2 CPUs ensures smooth PTY compilation and agent execution
          memory = "2Gi" # 2 GiB RAM
        }
        # Keep CPU allocated even when no requests are active to maintain WebSocket stability
        cpu_idle = false 
      }

      env {
        name  = "DEMO_REPO_PATH"
        value = "/workspace/todo-app"
      }
      env {
        name  = "USE_ADC"
        value = "true"
      }
      env {
        name  = "GOOGLE_GENAI_USE_VERTEXAI"
        value = "true"
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GOOGLE_CLOUD_LOCATION"
        value = var.region
      }
      env {
        name  = "GOOGLE_APPLICATION_CREDENTIALS"
        value = "/home/demo/.config/gcloud/application_default_credentials.json"
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.log_writer
  ]
}

# 5. Grant the IAP Service Agent permission to invoke the Cloud Run service
# This is mandatory for Direct IAP to function.
resource "google_cloud_run_v2_service_iam_member" "iap_invoker" {
  name     = google_cloud_run_v2_service.demo_service.name
  location = google_cloud_run_v2_service.demo_service.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-iap.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "demo_url" {
  value       = google_cloud_run_v2_service.demo_service.uri
  description = "The secure, IAP-protected URL of the Cloud Run demo service"
}
