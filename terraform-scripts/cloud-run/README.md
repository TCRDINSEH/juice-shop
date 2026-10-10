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

gcloud.cmd config set project $Project
gcloud.cmd auth configure-docker "$Region-docker.pkg.dev"

# Run once if the repository does not already exist.
gcloud.cmd artifacts repositories create $Repository `
  --repository-format=docker `
  --location=$Region `
  --project=$Project

docker build -f .\juice-shop\Dockerfile -t "$Registry/juice-shop:latest" .\juice-shop
docker push "$Registry/juice-shop:latest"

docker build -f .\terraform-scripts\cloud-run\scanner\Dockerfile `
  -t "$Registry/juice-shop-cve-exporter:latest" `
  .\terraform-scripts\cloud-run\scanner
docker push "$Registry/juice-shop-cve-exporter:latest"

# Confirm both images were pushed before running Terraform.
gcloud.cmd artifacts docker images list $Registry
```

Ensure the Artifact Registry repository exists and your identity has
`roles/artifactregistry.writer` before building and pushing.

### If Docker cannot connect to its engine on Windows

Start Docker Desktop and wait until it reports that its engine is running.
This app's Dockerfile uses Linux images, so Docker Desktop must be using its
Linux/WSL 2 engine. Verify from PowerShell:

```powershell
docker info
```

If Docker Desktop is unavailable, build in Google Cloud instead (this does not
use the local Docker daemon). Enable Cloud Build and submit each build from the
repository root:

```powershell
gcloud.cmd services enable cloudbuild.googleapis.com --project $Project

gcloud.cmd builds submit .\juice-shop `
  --tag "$Registry/juice-shop:latest" `
  --project $Project

gcloud.cmd builds submit .\terraform-scripts\cloud-run\scanner `
  --tag "$Registry/juice-shop-cve-exporter:latest" `
  --project $Project
```

The build log reports the Cloud Build execution identity as
`720054743088-compute@developer.gserviceaccount.com`. Grant that identity
Cloud Logging's Logs Writer role (use the service account email from your own
build output if it differs):

```powershell
$BuildServiceAccount = "720054743088-compute@developer.gserviceaccount.com"
gcloud.cmd projects add-iam-policy-binding $Project `
  --member="serviceAccount:$BuildServiceAccount" `
  --role="roles/logging.logWriter"
```

The identity also needs permission to push images to the repository. If a build
fails with an Artifact Registry permission error, grant writer access on that
repository:

```powershell
gcloud.cmd artifacts repositories add-iam-policy-binding $Repository `
  --location=$Region `
  --project=$Project `
  --member="serviceAccount:$BuildServiceAccount" `
  --role="roles/artifactregistry.writer"
```

Allow a short time for IAM changes to propagate, then rerun the failed
`gcloud.cmd builds submit` command.

### If the Juice Shop source build fails during frontend SBOM generation

If the Juice Shop image build fails with `Missing metafile:
dist/frontend/stats.json`, the frontend build did not produce the bundle
metadata required by its SBOM step. For an unmodified Juice Shop deployment,
you can avoid building the source locally or in Cloud Build and copy the
project's public Docker Hub image into your Artifact Registry repository:

```powershell
gcloud.cmd builds submit .\terraform-scripts\cloud-run `
  --config .\terraform-scripts\cloud-run\cloudbuild-import-juice-shop.yaml `
  --project $Project
```

The Cloud Build identity needs Artifact Registry Writer on the repository.
This imports the public `bkimminich/juice-shop:latest` image; it does not
include any local source changes. Verify the destination image before applying:

```powershell
gcloud.cmd artifacts docker images list $Registry --include-tags
```

Confirm `juice-shop` has the `latest` tag and that the
`juice-shop-cve-exporter` image is present too.

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
gcloud.cmd run jobs execute juice-shop-cve-export --region $Region --project $Project --wait
gcloud.cmd storage ls "gs://YOUR_BUCKET/cve-findings/**"
```

Review Cloud Run Job logs if the execution fails. The runtime service accounts
are scoped to Artifact Registry read, Artifact Analysis occurrence read, and
GCS object creation; the Scheduler identity can invoke only the scanner job.
To grant an individual user access to the private Juice Shop service:

```powershell
gcloud.cmd run services add-iam-policy-binding juice-shop `
  --region $Region `
  --project $Project `
  --member="user:YOUR_EMAIL" `
  --role="roles/run.invoker"
```
