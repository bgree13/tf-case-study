#!/usr/bin/env bash
# Creates the Terraform state bucket with the AWS CLI and verifies its settings.
# Usage: scripts/bootstrap-backend.sh <bucket-name> [region]

# Stop on the first error
set -e

BUCKET="$1"
REGION="${2:-us-east-1}"

if [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket-name> [region]"
  exit 1
fi

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

echo "==> Checking tools"
if ! command -v aws > /dev/null; then
  fail "aws CLI is not installed"
fi
pass "aws CLI found"

echo "==> Checking AWS credentials"
if ! ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text); then
  fail "no valid AWS credentials"
fi
pass "logged in to account $ACCOUNT_ID"

echo "==> Creating bucket $BUCKET in $REGION"
if aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
  echo "Bucket already exists, skipping create"
elif [ "$REGION" = "us-east-1" ]; then
  # us-east-1 rejects an explicit LocationConstraint
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" > /dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Verifying bucket $BUCKET"

if ! aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1; then
  fail "bucket not found or not accessible"
fi
pass "bucket exists"

VERSIONING=$(aws s3api get-bucket-versioning --bucket "$BUCKET" \
  --query Status --output text)
if [ "$VERSIONING" != "Enabled" ]; then
  fail "versioning is not enabled"
fi
pass "versioning enabled"

ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$BUCKET" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text)
if [ "$ENCRYPTION" != "AES256" ] && [ "$ENCRYPTION" != "aws:kms" ]; then
  fail "encryption is not configured"
fi
pass "encryption enabled ($ENCRYPTION)"

BLOCK_ACLS=$(aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text)
BLOCK_POLICY=$(aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration.BlockPublicPolicy' --output text)
IGNORE_ACLS=$(aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration.IgnorePublicAcls' --output text)
RESTRICT_BUCKETS=$(aws s3api get-public-access-block --bucket "$BUCKET" \
  --query 'PublicAccessBlockConfiguration.RestrictPublicBuckets' --output text)

if [ "$BLOCK_ACLS" != "True" ] || [ "$BLOCK_POLICY" != "True" ] || \
   [ "$IGNORE_ACLS" != "True" ] || [ "$RESTRICT_BUCKETS" != "True" ]; then
  fail "public access is not fully blocked"
fi
pass "public access blocked"

echo "==> Backend bucket ready."
echo "Next: terraform -chdir=terraform init -backend-config=\"bucket=$BUCKET\" -backend-config=\"region=$REGION\""
