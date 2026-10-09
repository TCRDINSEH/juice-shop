output "juice_shop_url" {
  description = "Cloud Run URL. With the default IAM policy, callers must be authenticated."
  value       = google_cloud_run_v2_service.juice_shop.uri
}

output "cve_report_bucket" {
  description = "GCS bucket receiving daily CSV exports."
  value       = google_storage_bucket.cve_reports.name
}

output "scanner_job_name" {
  description = "Cloud Run Job invoked by the daily Cloud Scheduler job."
  value       = google_cloud_run_v2_job.cve_scanner.name
}

output "scheduler_job_name" {
  description = "Cloud Scheduler job that starts the CVE exporter."
  value       = google_cloud_scheduler_job.daily_cve_export.name
}

output "artifact_registry_image_prefix" {
  description = "Use this prefix when tagging the CVE exporter image."
  value       = local.scanner_image
}
