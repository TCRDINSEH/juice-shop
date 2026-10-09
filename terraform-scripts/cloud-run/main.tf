terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_apis = toset([
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "containeranalysis.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com"
  ])

  scanner_image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repository_id}/juice-shop-cve-exporter:${var.scanner_image_tag}"
}

resource "google_project_service" "apis" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repository_id

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}

resource "google_service_account" "juice_shop" {
  account_id   = "juice-shop-runtime"
  display_name = "Juice Shop Cloud Run runtime"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_cloud_run_v2_service" "juice_shop" {
  name                = var.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.juice_shop.email

    scaling {
      max_instance_count = 2
    }

    containers {
      image = var.juice_shop_image

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
    data.google_artifact_registry_repository.images
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.juice_shop.location
  name     = google_cloud_run_v2_service.juice_shop.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_storage_bucket" "cve_reports" {
  name                        = var.csv_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.apis["storage.googleapis.com"]]
}

resource "google_service_account" "scanner" {
  account_id   = "juice-shop-cve-scanner"
  display_name = "Juice Shop Artifact Analysis exporter"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_project_iam_member" "scanner_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.scanner.email}"
}

resource "google_project_iam_member" "scanner_occurrences_viewer" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.viewer"
  member  = "serviceAccount:${google_service_account.scanner.email}"
}

resource "google_storage_bucket_iam_member" "scanner_csv_writer" {
  bucket = google_storage_bucket.cve_reports.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.scanner.email}"
}

resource "google_cloud_run_v2_job" "cve_scanner" {
  name                = var.scanner_job_name
  location            = var.region
  deletion_protection = false

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = google_service_account.scanner.email
      timeout         = "3600s"
      max_retries     = 1

      containers {
        image = local.scanner_image

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "GAR_LOCATION"
          value = var.region
        }

        env {
          name  = "GAR_REPOSITORY"
          value = data.google_artifact_registry_repository.images.repository_id
        }

        env {
          name  = "GCS_BUCKET"
          value = google_storage_bucket.cve_reports.name
        }

        env {
          name  = "GCS_PREFIX"
          value = var.csv_object_prefix
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis["run.googleapis.com"],
    google_project_service.apis["containeranalysis.googleapis.com"],
    google_project_iam_member.scanner_artifact_reader,
    google_project_iam_member.scanner_occurrences_viewer,
    google_storage_bucket_iam_member.scanner_csv_writer
  ]
}

resource "google_service_account" "scheduler" {
  account_id   = "juice-shop-cve-scheduler"
  display_name = "Juice Shop CVE Cloud Scheduler"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_job.cve_scanner.location
  name     = google_cloud_run_v2_job.cve_scanner.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "daily_cve_export" {
  name             = "daily-juice-shop-cve-export"
  region           = var.region
  schedule         = var.schedule
  time_zone        = var.schedule_time_zone
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${var.scanner_job_name}:run"
    body        = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.apis["cloudscheduler.googleapis.com"],
    google_cloud_run_v2_job_iam_member.scheduler_invoker
  ]
}
