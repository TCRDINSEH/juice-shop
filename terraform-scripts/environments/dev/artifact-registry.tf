resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Docker images for the centralized vulnerability registry project"
  format        = "DOCKER"

  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
}
