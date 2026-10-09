# Cloud Run deployment and daily Artifact Registry CVE export

This stack deploys OWASP Juice Shop as a Cloud Run service, runs a Cloud Run Job
once a day to query Artifact Analysis vulnerability occurrences for every image
digest in the configured Artifact Registry Docker repository, and uploads a
timestamped CSV to a private Cloud Storage bucket.

The service is private by default because Juice Shop is intentionally
vulnerable. Set `allow_unauthenticated = true` only for a controlled, isolated
demonstration. Public access can expose the app and its known vulnerabilities to
the internet.

## Prerequisites

- A Google Cloud project with billing enabled and permissions to enable APIs,
  build images, and create Cloud Run, Cloud Scheduler, IAM, Artifact Registry,
  and Cloud Storage resources.
- `gcloud`, Docker, and Terraform 1.5 or later.
- An existing Artifact Registry Docker repository in the selected region. The
  default is the `vulnerability-registry` repository from the dev Terraform
  configuration.
- Artifact Analysis vulnerability scanning enabled for the project/repository.
  Findings are available only after image scanning completes.

The pre-existing `terraform-scripts/environments/dev` Terraform root has
unresolved GKE and Cloud SQL output references. This deployment uses its own
Terraform root and state; it does not apply or modify that existing state.

## Build and push images

Run these commands from the repository root in PowerShell. Replace the project
ID and bucket name; the bucket name must be globally unique.

```powershell
$Project = "YOUR_PROJECT_ID"
$Region = "asia-south1"
$Repository = "vulnerability-registry"
$Registry = "$Region-docker.pkg.dev/$Project/$Repository"

gcloud config set project $Project
gcloud auth configure-docker "$Region-docker.pkg.dev"

# Run once if the repository does not already exist.
gcloud artifacts repositories create $Repository `
  --repository-format=docker `
  --location=$Region `
  --project=$Project

docker build -f .\juice-shop\Dockerfile -t "$Registry/juice-shop:latest" .\juice-shop
docker push "$Registry/juice-shop:latest"

docker build -f .\terraform-scripts\cloud-run\scanner\Dockerfile `
  -t "$Registry/juice-shop-cve-exporter:latest" `
  .\terraform-scripts\cloud-run\scanner
docker push "$Registry/juice-shop-cve-exporter:latest"
```

Ensure the Artifact Registry repository exists and your identity has
`roles/artifactregistry.writer` before building and pushing.

## Configure and apply

```powershell
Set-Location .\terraform-scripts\cloud-run
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Set `project_id`, the globally unique `csv_bucket_name`, and
`juice_shop_image` in `terraform.tfvars`. Then:

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

The default schedule is `0 2 * * *` in `Etc/UTC` (daily at 02:00 UTC). Set
`schedule_time_zone` and `schedule` to change it. The exporter creates one CSV
per run under
`gs://BUCKET/cve-findings/YYYY/MM/DD/cves-YYYYMMDDTHHMMSSZ.csv`. The CSV has a
header even when no CVE findings are available. Each output row represents a
CVE/package finding and includes the image digest, severity, installed/fixed
versions, description, and references.

## Verify and operate

```powershell
terraform output
gcloud run jobs execute juice-shop-cve-export --region $Region --project $Project --wait
gcloud storage ls "gs://YOUR_BUCKET/cve-findings/**"
```

Review Cloud Run Job logs if the execution fails. The runtime service accounts
are scoped to Artifact Registry read, Artifact Analysis occurrence read, and
GCS object creation; the Scheduler identity can invoke only the scanner job.
To grant an individual user access to the private Juice Shop service:

```powershell
gcloud run services add-iam-policy-binding juice-shop `
  --region $Region `
  --project $Project `
  --member="user:YOUR_EMAIL" `
  --role="roles/run.invoker"
```
