#!/usr/bin/env bash
# Creates the GitHub OIDC provider and an IAM role that GitHub Actions can assume.
# Usage: scripts/setup-github-oidc.sh <github-owner/repo> <state-bucket> [region]

# Stop on the first error
set -e

REPO="$1"
BUCKET="$2"
REGION="${3:-us-east-1}"
APP_NAME="tf-case-study"
ROLE_NAME="$APP_NAME-github-actions"

if [ -z "$REPO" ] || [ -z "$BUCKET" ]; then
  echo "Usage: $0 <github-owner/repo> <state-bucket> [region]"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROVIDER_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
echo "==> Using account $ACCOUNT_ID"

echo "==> Creating GitHub OIDC provider"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" > /dev/null 2>&1; then
  echo "OIDC provider already exists, skipping"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 > /dev/null
fi

# Only main-branch pushes and pull requests from this repo can assume the role
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$PROVIDER_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:$REPO:ref:refs/heads/main",
          "repo:$REPO:pull_request"
        ]
      }
    }
  }]
}
EOF
)

PERMISSIONS_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateBucketList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::$BUCKET"
    },
    {
      "Sid": "StateObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::$BUCKET/app/*"
    },
    {
      "Sid": "LambdaFunction",
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$APP_NAME"
    },
    {
      "Sid": "ApiGateway",
      "Effect": "Allow",
      "Action": ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE", "apigateway:TagResource", "apigateway:UntagResource"],
      "Resource": "arn:aws:apigateway:$REGION::/*"
    },
    {
      "Sid": "LogGroup",
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:/aws/lambda/$APP_NAME*"
    },
    {
      "Sid": "DescribeLogGroups",
      "Effect": "Allow",
      "Action": "logs:DescribeLogGroups",
      "Resource": "*"
    },
    {
      "Sid": "LambdaExecutionRole",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
        "iam:UpdateAssumeRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies", "iam:ListRolePolicies", "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::$ACCOUNT_ID:role/$APP_NAME-lambda-role"
    },
    {
      "Sid": "PassRoleToLambda",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::$ACCOUNT_ID:role/$APP_NAME-lambda-role",
      "Condition": { "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" } }
    }
  ]
}
EOF
)

echo "==> Creating IAM role $ROLE_NAME"
if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
  echo "Role already exists, updating trust policy"
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
else
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" > /dev/null
fi

aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name terraform-deploy --policy-document "$PERMISSIONS_POLICY"

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)

echo "==> Done. Add these GitHub repository variables (Settings > Secrets and variables > Actions > Variables):"
echo "AWS_ROLE_ARN    = $ROLE_ARN"
echo "TF_STATE_BUCKET = $BUCKET"
echo "AWS_REGION      = $REGION"
