#!/usr/bin/env bash
# github-secrets-bootstrap.sh
# Sets GitHub repo secrets and variables needed by the CI/CD workflows.
#
# Required env vars:
#   REPO                  (format: owner/repo)
#   AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
#   TFSTATE_RESOURCE_GROUP, TFSTATE_STORAGE_ACCOUNT, TFSTATE_CONTAINER

set -euo pipefail

: "${REPO:?Set REPO as owner/repo}"
: "${AZURE_CLIENT_ID:?Set AZURE_CLIENT_ID}"
: "${AZURE_TENANT_ID:?Set AZURE_TENANT_ID}"
: "${AZURE_SUBSCRIPTION_ID:?Set AZURE_SUBSCRIPTION_ID}"
: "${TFSTATE_RESOURCE_GROUP:?Set TFSTATE_RESOURCE_GROUP}"
: "${TFSTATE_STORAGE_ACCOUNT:?Set TFSTATE_STORAGE_ACCOUNT}"
: "${TFSTATE_CONTAINER:?Set TFSTATE_CONTAINER}"

gh auth status >/dev/null

echo "▶ Setting secrets on $REPO ..."
echo "$AZURE_CLIENT_ID"       | gh secret set AZURE_CLIENT_ID       -R "$REPO"
echo "$AZURE_TENANT_ID"       | gh secret set AZURE_TENANT_ID       -R "$REPO"
echo "$AZURE_SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID -R "$REPO"

echo "▶ Setting variables on $REPO ..."
gh variable set TFSTATE_RESOURCE_GROUP   --body "$TFSTATE_RESOURCE_GROUP"   -R "$REPO"
gh variable set TFSTATE_STORAGE_ACCOUNT  --body "$TFSTATE_STORAGE_ACCOUNT"  -R "$REPO"
gh variable set TFSTATE_CONTAINER        --body "$TFSTATE_CONTAINER"         -R "$REPO"

echo "✅ DONE — secrets and variables set on $REPO"
