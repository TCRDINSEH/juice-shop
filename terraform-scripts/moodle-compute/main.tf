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
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com"
  ])
}

resource "google_project_service" "apis" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "moodle" {
  name                    = var.network_name
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "moodle" {
  name                     = var.subnetwork_name
  region                   = var.region
  network                  = google_compute_network.moodle.id
  ip_cidr_range            = var.subnetwork_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_services" {
  name          = "${var.network_name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.moodle.id

  depends_on = [google_project_service.apis["servicenetworking.googleapis.com"]]
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.moodle.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_sql_database_instance" "moodle" {
  name                = var.sql_instance_name
  region              = var.region
  database_version    = "MYSQL_8_0"
  deletion_protection = false

  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.sql_disk_size_gb
    disk_autoresize   = true

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.moodle.id
    }
  }

  depends_on = [
    google_project_service.apis["sqladmin.googleapis.com"],
    google_service_networking_connection.private_services
  ]
}

resource "google_sql_database" "moodle" {
  name      = var.sql_database_name
  instance  = google_sql_database_instance.moodle.name
  charset   = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
}

resource "google_sql_user" "moodle" {
  name     = var.sql_username
  instance = google_sql_database_instance.moodle.name
  password = var.sql_password
}

resource "google_secret_manager_secret" "sql_password" {
  secret_id = "${var.sql_instance_name}-moodle-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "sql_password" {
  secret      = google_secret_manager_secret.sql_password.id
  secret_data = var.sql_password
}

resource "google_secret_manager_secret" "admin_password" {
  secret_id = "${var.vm_name}-admin-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis["secretmanager.googleapis.com"]]
}

resource "google_secret_manager_secret_version" "admin_password" {
  secret      = google_secret_manager_secret.admin_password.id
  secret_data = var.admin_password
}

resource "google_service_account" "vm" {
  account_id   = var.vm_service_account_id
  display_name = "Moodle VM runtime"

  depends_on = [google_project_service.apis["iam.googleapis.com"]]
}

resource "google_secret_manager_secret_iam_member" "vm_sql_password" {
  secret_id = google_secret_manager_secret.sql_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_admin_password" {
  secret_id = google_secret_manager_secret.admin_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_address" "moodle" {
  name   = "${var.vm_name}-ip"
  region = var.region
}

resource "google_compute_disk" "moodledata" {
  name = "${var.vm_name}-data"
  zone = var.zone
  type = "pd-balanced"
  size = var.moodledata_disk_size_gb
}

resource "google_compute_firewall" "http" {
  name    = "${var.network_name}-allow-http"
  network = google_compute_network.moodle.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["moodle-web"]
}

resource "google_compute_instance" "moodle" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["moodle-web"]

  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.moodledata.id
    device_name = "moodledata"
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.moodle.id

    access_config {
      nat_ip = google_compute_address.moodle.address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    admin_email_b64       = base64encode(var.admin_email)
    admin_firstname_b64   = base64encode(var.admin_firstname)
    admin_lastname_b64    = base64encode(var.admin_lastname)
    admin_secret_name_b64 = base64encode(google_secret_manager_secret.admin_password.secret_id)
    admin_username_b64    = base64encode(var.admin_username)
    database_name_b64     = base64encode(google_sql_database.moodle.name)
    database_secret_b64   = base64encode(google_secret_manager_secret.sql_password.secret_id)
    database_username_b64 = base64encode(google_sql_user.moodle.name)
    moodle_branch_b64     = base64encode(var.moodle_branch)
    moodledata_path       = "/var/lib/moodledata"
    project_id_b64        = base64encode(var.project_id)
    site_fullname_b64     = base64encode(var.site_fullname)
    site_shortname_b64    = base64encode(var.site_shortname)
    sql_private_ip        = google_sql_database_instance.moodle.private_ip_address
    wwwroot               = "http://${google_compute_address.moodle.address}"
  })

  depends_on = [
    google_project_service.apis["compute.googleapis.com"],
    google_secret_manager_secret_iam_member.vm_sql_password,
    google_secret_manager_secret_iam_member.vm_admin_password,
    google_sql_database.moodle,
    google_sql_user.moodle
  ]
}
