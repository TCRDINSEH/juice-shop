# GCP Cloud-Native Centralized Vulnerability Registry — Terraform baseline

## Cloud Run alternative

For a separate deployment of OWASP Juice Shop on Cloud Run with a daily Cloud
Scheduler job that exports Artifact Registry CVE findings to a private GCS
bucket, follow [the Cloud Run deployment guide](./terraform-scripts/cloud-run/README.md).
This stack uses its own Terraform state and does not require applying the
incomplete GKE/Cloud SQL configuration described below.

This Terraform baseline creates:
- Required Google Cloud APIs
- A custom VPC and subnet with secondary IP ranges for GKE
- GKE Autopilot cluster
- Artifact Registry Docker repository
- Cloud SQL for PostgreSQL (Enterprise edition, small development tier)
- Security API and GitHub Actions service accounts
- Secret Manager secret container for the database password
- Optional GitHub Actions Workload Identity Federation (WIF)

Cloud Armor is intentionally not created by default. Enable it later only after confirming the project's security-policy quota.

## Prerequisites

1. A Google Cloud project with billing enabled.
2. `gcloud`, Terraform, `kubectl`, and Docker installed locally.
3. Permissions to enable APIs, create networking/GKE/Cloud SQL/Artifact Registry resources, and manage IAM.
4. Confirm the project ID in `terraform.tfvars.example` before applying.

## Windows PowerShell quick start

From this directory (`terraform-scripts/environments/dev`):

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and confirm project_id and region.
# Leave enable_github_wif = false for the first apply.

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Terraform will prompt for `db_password`. Use a strong password and store it safely.
**Important:** Terraform's local state can contain the database password. Never commit `terraform.tfstate`, `terraform.tfstate.backup`, or `terraform.tfvars`. Use a secured remote state backend before collaborating or using this for anything beyond a student lab.

## After apply

1. Open Google Cloud Console → Secret Manager → `registry-db-password`.
2. Add a secret version containing the same password you supplied to Terraform. Terraform creates the secret container but intentionally does not create a secret version.
3. Check outputs:
   ```powershell
   terraform output
   gcloud container clusters get-credentials cn-vul-reg-gke --region=asia-south1 --project=YOUR_PROJECT_ID
   kubectl get namespaces
   ```
   An idle Autopilot cluster might not show nodes until you deploy a workload.
4. Push an image to Artifact Registry using the URI shown by `terraform output artifact_registry_uri`.

## Optional GitHub Actions Workload Identity Federation

1. Set these in `terraform.tfvars`:
   ```hcl
   enable_github_wif = true
   github_owner      = "YOUR_GITHUB_USERNAME_OR_ORG"
   github_repo       = "YOUR_REPOSITORY_NAME"
   ```
2. Run `terraform plan` and review the IAM changes, then `terraform apply`.
3. Copy the outputs `github_actions_workload_identity_provider` and `github_actions_service_account` into GitHub repository secrets named `GCP_WIF_PROVIDER` and `GCP_DEPLOYER_SA`.
4. Keep the provider's repository condition restricted to your own repository.

## Important cost and safety notes

- Cloud SQL bills while the instance exists, even if it is idle. GKE, storage, network egress, and AI usage may also incur charges.
- Create a Cloud Billing budget and alerts before applying.
- Cloud SQL is assigned a public IP, but this configuration does not add public authorized networks. Connect through the Cloud SQL Auth Proxy/connector and IAM permissions; do not open the database to `0.0.0.0/0`.
- The `db-f1-micro` tier is for low-cost development/testing, not production.
- This baseline deliberately omits Cloud Armor due to a previously encountered zero quota for security policies. It also omits a public load balancer so the deliberately vulnerable Juice Shop can be tested privately first.
- Do not run `terraform destroy` unless you intend to delete the GKE cluster, database, and registry resources.
