output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}

output "gke_get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region=${var.region} --project=${var.project_id}"
}

output "artifact_registry_uri" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "cloud_sql_connection_name" {
  value = google_sql_database_instance.registry.connection_name
}

output "cloud_sql_database_name" {
  value = google_sql_database.registry.name
}

output "security_api_service_account" {
  value = google_service_account.security_api.email
}

output "github_actions_service_account" {
  value = google_service_account.github_deployer.email
}

output "github_actions_workload_identity_provider" {
  value = try(google_iam_workload_identity_pool_provider.github[0].name, null)
}

output "database_password_secret_id" {
  value = google_secret_manager_secret.db_password.secret_id
}
