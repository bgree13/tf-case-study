# tf-case-study

A Python 3.12 Lambda HTTP app deployed with Terraform behind an API Gateway HTTP API.

## API

- `GET /` returns a hello message.
- `GET /health` returns a health status.
- `POST /echo` returns the submitted JSON body.

## Deploy locally

Requirements: Terraform 1.10+, AWS CLI credentials, and an S3 bucket for Terraform state.

Create the state bucket first. Choose a globally unique bucket name; the optional region defaults to `us-east-1`:

```sh
bash scripts/bootstrap-backend.sh <bucket-name> [region]
```

The script creates the bucket if needed, enables versioning and encryption, blocks public access, and verifies those settings. Then initialize Terraform with the same bucket name and region:

```sh
terraform -chdir=terraform init \
  -backend-config="bucket=<bucket-name>" \
  -backend-config="region=us-east-1"
terraform -chdir=terraform apply
```

Terraform prints the API URL after deployment. The state bucket is separate from the app and is not removed by the destroy workflow.

## GitHub Actions

The deploy workflow validates and plans pull requests, then applies on pushes to `main`. It uses GitHub OIDC; AWS access keys are **NOT** stored in GitHub.

1. Create the OIDC provider and deploy role with `bash scripts/setup-github-oidc.sh <github-oidc-repo-subject> <state-bucket> [region]`. Use the repo subject expected by the AWS trust policy.
2. Add the printed values as repository **Actions variables**: `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, and `AWS_REGION`.
3. Push to `main` to deploy. To destroy, run **Destroy Terraform infrastructure** from the Actions tab on `main` and select `yes`.

The destroy workflow removes Terraform-managed app resources, not the state bucket or GitHub OIDC role.
