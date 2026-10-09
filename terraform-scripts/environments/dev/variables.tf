variable "project_id" {
  description = "Existing Google Cloud project ID. The project must have billing enabled."
  type        = string
}

variable "region" {
  description = "Google Cloud region for regional resources."
  type        = string
  default     = "asia-south1"
}

variable "cluster_name" {
  description = "Name of the GKE Autopilot cluster."
  type        = string
  default     = "cn-vul-reg-gke"
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "vulnerability-registry"
}

variable "sql_instance_name" {
  description = "Cloud SQL instance name."
  type        = string
  default     = "vuln-registry-db"
}

variable "sql_database_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "vulnerability_registry"
}

variable "sql_user_name" {
  description = "Application database user."
  type        = string
  default     = "registry_app"
}

variable "db_password" {
  description = "Strong password for the Cloud SQL application user. Terraform state will contain this value."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 12
    error_message = "db_password must contain at least 12 characters."
  }
}

variable "enable_github_wif" {
  description = "Create a GitHub Actions Workload Identity Federation provider. Set true only after setting owner and repository."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "GitHub username or organization that owns the repository."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name, without owner or URL."
  type        = string
  default     = ""
}
