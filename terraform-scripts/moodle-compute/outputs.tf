output "moodle_url" {
  description = "HTTP URL for the Moodle site. Configure HTTPS before using real student data."
  value       = "http://${google_compute_address.moodle.address}"
}

output "moodle_vm_name" {
  description = "Compute Engine VM hosting Moodle."
  value       = google_compute_instance.moodle.name
}

output "moodle_admin_username" {
  description = "Initial Moodle administrator username."
  value       = var.admin_username
}

output "sql_private_ip" {
  description = "Private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.moodle.private_ip_address
}

output "sql_instance_name" {
  description = "Cloud SQL MySQL instance name."
  value       = google_sql_database_instance.moodle.name
}

output "moodledata_disk_name" {
  description = "Persistent disk holding Moodle uploads and generated data."
  value       = google_compute_disk.moodledata.name
}
