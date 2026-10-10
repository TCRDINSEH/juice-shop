output "moodle_url" {
  description = "HTTPS URL of the Moodle Cloud Run service."
  value       = google_cloud_run_v2_service.moodle.uri
}

output "moodle_admin_username" {
  description = "Initial Moodle administrator username."
  value       = var.admin_username
}

output "moodledata_bucket" {
  description = "Private Cloud Storage bucket mounted as Moodle's persistent file area."
  value       = google_storage_bucket.moodledata.name
}

output "sql_instance_name" {
  description = "Cloud SQL MySQL instance name."
  value       = google_sql_database_instance.moodle.name
}

output "cron_job_name" {
  description = "Cloud Run Job that executes Moodle scheduled tasks."
  value       = google_cloud_run_v2_job.cron.name
}
