variable "project_id" {
  description = "Google Cloud project ID with billing enabled."
  type        = string
}

variable "region" {
  description = "Region for the network, Cloud SQL instance, and VM address."
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "Compute Engine zone for the VM and persistent Moodle data disk."
  type        = string
  default     = "asia-south1-a"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "The VM zone must be in the selected region."
  }
}

variable "network_name" {
  description = "Name of the dedicated Moodle VPC network."
  type        = string
  default     = "moodle-vpc"
}

variable "subnetwork_name" {
  description = "Name of the Moodle subnet."
  type        = string
  default     = "moodle-subnet"
}

variable "subnetwork_cidr" {
  description = "IPv4 CIDR range for the Moodle subnet."
  type        = string
  default     = "10.40.0.0/24"
}

variable "sql_instance_name" {
  description = "Cloud SQL MySQL instance name."
  type        = string
  default     = "moodle-mysql"
}

variable "sql_tier" {
  description = "Cloud SQL machine tier. Use a production tier for real workloads."
  type        = string
  default     = "db-f1-micro"
}

variable "sql_disk_size_gb" {
  description = "Initial Cloud SQL disk size in GB; automatic storage increase is enabled."
  type        = number
  default     = 10
}

variable "sql_database_name" {
  description = "Moodle database name."
  type        = string
  default     = "moodle"
}

variable "sql_username" {
  description = "Application database username."
  type        = string
  default     = "moodle_app"
}

variable "sql_password" {
  description = "Strong application database password, also stored in Secret Manager."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_password) >= 16
    error_message = "The database password must contain at least 16 characters."
  }
}

variable "vm_name" {
  description = "Compute Engine VM name."
  type        = string
  default     = "moodle-web"
}

variable "vm_service_account_id" {
  description = "Service account ID used by the Moodle VM."
  type        = string
  default     = "moodle-vm-runtime"
}

variable "machine_type" {
  description = "Compute Engine machine type for the Moodle VM."
  type        = string
  default     = "e2-standard-2"
}

variable "moodledata_disk_size_gb" {
  description = "Persistent disk size for Moodle uploads and generated files."
  type        = number
  default     = 50
}

variable "moodle_branch" {
  description = "Moodle stable Git branch to install."
  type        = string
  default     = "MOODLE_501_STABLE"

  validation {
    condition     = can(regex("^MOODLE_[0-9]+_STABLE$", var.moodle_branch))
    error_message = "Use a Moodle stable branch name, such as MOODLE_501_STABLE."
  }
}

variable "site_fullname" {
  description = "Full name shown for the Moodle site."
  type        = string
  default     = "Moodle Learning Site"
}

variable "site_shortname" {
  description = "Short Moodle site name."
  type        = string
  default     = "Moodle"
}

variable "admin_username" {
  description = "Username for the initial Moodle site administrator."
  type        = string
  default     = "siteadmin"
}

variable "admin_password" {
  description = "Strong initial Moodle administrator password, also stored in Secret Manager."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.admin_password) >= 16 &&
      can(regex("[a-z]", var.admin_password)) &&
      can(regex("[A-Z]", var.admin_password)) &&
      can(regex("[0-9]", var.admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.admin_password))
    )
    error_message = "The administrator password must be at least 16 characters and include lowercase, uppercase, numeric, and non-alphanumeric characters."
  }
}

variable "admin_email" {
  description = "Email address for the initial Moodle site administrator."
  type        = string

  validation {
    condition     = can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", var.admin_email))
    error_message = "Provide a valid administrator email address."
  }
}

variable "admin_firstname" {
  description = "First name for the initial Moodle site administrator."
  type        = string
  default     = "Site"
}

variable "admin_lastname" {
  description = "Last name for the initial Moodle site administrator."
  type        = string
  default     = "Administrator"
}
