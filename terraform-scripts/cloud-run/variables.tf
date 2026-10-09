variable "project_id" {
  description = "Google Cloud project ID with billing enabled."
  type        = string
}

variable "region" {
  description = "Region containing the Artifact Registry repository and Cloud Run resources."
  type        = string
  default     = "asia-south1"
}

variable "artifact_repository_id" {
  description = "Existing Artifact Registry Docker repository containing the Juice Shop image."
  type        = string
  default     = "vulnerability-registry"
}

variable "juice_shop_image" {
  description = "Full Artifact Registry URI and tag/digest to deploy as the Juice Shop service."
  type        = string
}

variable "scanner_image_tag" {
  description = "Tag used for the CVE export job image."
  type        = string
  default     = "latest"
}

variable "csv_bucket_name" {
  description = "Globally unique GCS bucket name for timestamped CVE CSV reports."
  type        = string
}

variable "csv_object_prefix" {
  description = "Object prefix inside the report bucket."
  type        = string
  default     = "cve-findings"
}

variable "schedule" {
  description = "Cloud Scheduler cron expression for the daily export."
  type        = string
  default     = "0 2 * * *"
}

variable "schedule_time_zone" {
  description = "IANA time zone used to interpret the schedule."
  type        = string
  default     = "Etc/UTC"
}

variable "service_name" {
  description = "Cloud Run service name for OWASP Juice Shop."
  type        = string
  default     = "juice-shop"
}

variable "scanner_job_name" {
  description = "Cloud Run Job name for exporting Artifact Analysis CVE findings."
  type        = string
  default     = "juice-shop-cve-export"
}

variable "allow_unauthenticated" {
  description = "Allow public internet users to invoke the deliberately vulnerable Juice Shop service."
  type        = bool
  default     = false
}
