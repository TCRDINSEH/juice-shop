# Moodle on Cloud Run with the existing CVE CSV exporter

This is a separate Moodle deployment. It leaves the Juice Shop Cloud Run
service and its Terraform state unchanged.

The Moodle web service runs on Cloud Run, Moodle's supported MySQL database
runs on Cloud SQL, and a separate private Cloud Storage bucket holds Moodle's
file data and generated configuration. A Cloud Run Job and Cloud Scheduler run
Moodle's scheduled tasks. The existing Juice Shop CVE exporter scans every
image digest in its configured Artifact Registry repository; building Moodle
into that same repository includes its image in the existing daily CVE CSV
export. Vulnerability reports remain in the existing CVE bucket under its
configured prefix (normally `cve-findings`).

## Important demo limitations

- A Cloud Storage volume uses Cloud Storage FUSE, which does not provide full
  POSIX semantics or file locking. This configuration selects Moodle's
  database-backed lock factory, limits the web service to one instance, and is
  for a short classroom demonstration only. Do not use it for production or
  real student records.
- Moodle still needs SQL for courses, accounts, grades, and application state.
  Cloud Run can scale to zero, but Cloud SQL continues to incur charges while
  running. The shared-core SQL tier is a low-capacity demo setting, not a
  production recommendation.
- Terraform state contains the database and administrator passwords. Keep the
  local state and `terraform.tfvars` private; use a secured remote backend if
  sharing this deployment.
- The Moodle data bucket and CVE report bucket are deliberately separate.
  Vulnerability CSV files are written by the existing exporter, not by Moodle.
- Moodle's container image is built from the selected stable Moodle Git branch.
  Review that branch and its PHP requirements before changing versions.
- The example is private by default. Enabling unauthenticated access exposes the
  site to anyone with its URL; do not collect real student data over this demo
  setup.

## Prerequisites

- Google Cloud project with billing enabled and permissions to enable APIs and
  create Cloud Run, Cloud SQL, Cloud Scheduler, Artifact Registry, IAM, Secret
  Manager, and Cloud Storage resources.
- `gcloud`, Docker, and Terraform 1.5 or later.
- Artifact Analysis vulnerability scanning enabled.
- The existing `vulnerability-registry` Artifact Registry repository and the
  Juice Shop CVE exporter stack deployed in `terraform-scripts/cloud-run`.

The CVE scanner lists all image digests in its configured Artifact Registry
repository. Do not deploy this Moodle image to a different repository if you
want the existing scanner to include it.

## Build and push the Moodle image

Run from the repository root in PowerShell. Use the same project, region, and
Artifact Registry repository configured in the Juice Shop Cloud Run stack:

```powershell
$Project = "YOUR_PROJECT_ID"
$Region = "asia-south1"
$Repository = "vulnerability-registry"
$Registry = "$Region-docker.pkg.dev/$Project/$Repository"

gcloud.cmd auth configure-docker "$Region-docker.pkg.dev"

docker build `
  --build-arg MOODLE_BRANCH=MOODLE_501_STABLE `
  -t "$Registry/moodle:latest" `
  .\terraform-scripts\cloud-run-moodle\app

docker push "$Registry/moodle:latest"
gcloud.cmd artifacts docker images list $Registry --include-tags
```

If Docker Desktop is unavailable, enable Cloud Build and build from the
repository root instead:

```powershell
gcloud.cmd services enable cloudbuild.googleapis.com --project $Project
gcloud.cmd builds submit .\terraform-scripts\cloud-run-moodle\app `
  --tag "$Registry/moodle:latest" `
  --project $Project
```

Artifact Analysis scanning is asynchronous. Allow time for the Moodle image's
findings to appear before the existing scheduled export runs.

## Configure and deploy Moodle

```powershell
Set-Location .\terraform-scripts\cloud-run-moodle
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit `terraform.tfvars`:

- Set the project ID and `moodle_image` to the image just pushed.
- Provide a globally unique `moodledata_bucket_name`.
- Set the administrator email and two different strong passwords, each at
  least 16 characters.
- Leave `allow_unauthenticated = false` for a private service. Set it to `true`
  only if your instructor needs a public classroom demo.

Then run:

```powershell
gcloud.cmd auth application-default login
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

The initial Cloud Run startup installs Moodle into Cloud SQL and writes
Moodle's persistent configuration to the private Moodle data bucket. First
startup can take several minutes.

## Open the service and review vulnerability reports

```powershell
terraform output
```

With the default private IAM policy, grant access to specific users:

```powershell
gcloud.cmd run services add-iam-policy-binding moodle `
  --region $Region `
  --project $Project `
  --member="user:YOUR_EMAIL" `
  --role="roles/run.invoker"
```

Sign in with the reported `moodle_admin_username` and the `admin_password`
entered in the local `terraform.tfvars`.

The existing Juice Shop CVE exporter continues writing timestamped CSV reports
to its existing bucket. To run it immediately:

```powershell
gcloud.cmd run jobs execute juice-shop-cve-export `
  --region $Region `
  --project $Project `
  --wait

gcloud.cmd storage ls "gs://YOUR_EXISTING_CVE_BUCKET/cve-findings/**"
```

The report includes CVEs for all images in the configured Artifact Registry
repository, including `moodle` after Artifact Analysis has finished scanning it.
Review Cloud Run Job logs if a scan execution fails.

## Cost and cleanup

Cloud Run scales the web service to zero when idle; Cloud SQL does not. Cloud
SQL is likely to be the main ongoing cost, with smaller charges possible for
storage, Artifact Registry, Cloud Scheduler, and network use. Check current
regional pricing and billing before deploying.

After the demo, remove only the Moodle stack:

```powershell
terraform destroy
```

Review the destroy plan carefully. It removes the Moodle database, Moodle data
bucket, and Cloud Run resources. It does not remove Juice Shop or its CVE report
bucket. The Moodle bucket has `force_destroy = false`; empty it through a
reviewed, targeted operation before destroying if it contains any objects.
