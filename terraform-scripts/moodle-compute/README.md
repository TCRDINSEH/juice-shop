# Moodle on Compute Engine with Cloud SQL

This separate Terraform root deploys Moodle to a Compute Engine VM, stores
Moodle uploads and generated data on a persistent disk, and uses a private-IP
Cloud SQL for MySQL instance. It does not alter the Juice Shop Cloud Run
configuration or its Terraform state.

The example is intended for a learning/demo environment. It exposes Moodle over
HTTP and creates a small, zonal database instance. Do not use real student or
other sensitive data until HTTPS, backups/recovery, monitoring, and production
capacity have been configured.

## Prerequisites

- A Google Cloud project with billing enabled and permission to enable APIs and
  create Compute Engine, Cloud SQL, VPC peering, IAM, and Secret Manager
  resources.
- `gcloud` and Terraform 1.5 or later.

The VM uses Debian 12, installs Moodle from the selected stable branch, and
runs Moodle's CLI installer at first boot. The initial database and admin
passwords are stored in Secret Manager and fetched by the VM's dedicated service
account. Terraform state also contains these secret values; protect the state
and use a secured remote backend for shared or production use.

## Configure and deploy

From PowerShell at the repository root:

```powershell
Set-Location .\terraform-scripts\moodle-compute
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit `terraform.tfvars`. Set your project ID, administrator email, and two
different strong passwords (at least 16 characters each). The sample defaults
to `asia-south1`; change both `region` and `zone` together if needed.

Then deploy:

```powershell
gcloud.cmd auth application-default login
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

The initial boot installs packages, downloads the Moodle stable branch, mounts
the persistent Moodle data disk, installs Moodle and its initial administrator
account, and configures the Moodle cron task. Boot setup can take several
minutes. Terraform does not wait for the application installer to finish.

## Open Moodle

Get the site URL and initial admin username:

```powershell
terraform output
```

Open `moodle_url` in a browser and sign in with `moodle_admin_username` and the
`admin_password` from your local `terraform.tfvars`.

The site is publicly reachable over HTTP, while MySQL is reachable only over
the private VPC connection. The VM has no SSH ingress rule. To inspect
first-boot progress, use Cloud Console's VM serial port output or:

```powershell
gcloud.cmd compute instances get-serial-port-output moodle-web `
  --zone asia-south1-a `
  --project YOUR_PROJECT_ID
```

## Important operations

- Keep `terraform.tfvars` and Terraform state private. Do not commit either.
- The passwords in `terraform.tfvars` are used for the initial installation.
  Changing `admin_password` does not reset an existing Moodle account, and
  changing `sql_password` requires a coordinated database and Moodle
  configuration update.
- The Moodle data disk is separate from the VM boot disk and is retained if the
  VM is replaced. It also retains Moodle's generated configuration so the site
  can reconnect to its database after a VM replacement. Back up this disk and
  the Cloud SQL instance before upgrades or destructive operations.
- The example uses HTTP and a public IP for convenience. Configure HTTPS and a
  domain before collecting or storing real student data.
- The default `db-f1-micro` tier is for low-volume learning only. Increase the
  Cloud SQL tier, VM size, disk capacity, and availability for real workloads.
- Cloud SQL automated backups are enabled, but they are not a substitute for
  tested restore procedures.
- To remove the resources, run `terraform destroy` from this directory. Review
  the plan carefully: it deletes the database and its backups as well as the VM
  and persistent Moodle data disk.
