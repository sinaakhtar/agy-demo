variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "The name of the Cloud Run service"
  type        = string
  default     = "antigravity-demo"
}

variable "image_uri" {
  description = "The Docker image URI to deploy to Cloud Run"
  type        = string
}
