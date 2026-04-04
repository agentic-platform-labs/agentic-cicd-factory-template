#!/usr/bin/env bash
# azure-oidc-bootstrap-one-sp.sh
# Creates one Entra App Registration with 5 federated identity credentials
# (one per GitHub Actions trigger: PR, main push, dev/test/prod environments).
#
# Required env vars:
#   SUBSCRIPTION_ID, TENANT_ID, GITHUB_OWNER, GITHUB_REPO
# Optional:
#   APP_NAME          (default: ${GITHUB_REPO}-oidc)
#   ENVIRONMENTS      (default: "dev test prod")
#   ROLE_NAME         (default: Contributor)

set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${TENANT_ID:?Set TENANT_ID}"
: "${GITHUB_OWNER:?Set GITHUB_OWNER}"
: "${GITHUB_REPO:?Set GITHUB_REPO}"

APP_NAME="${APP_NAME:-${GITHUB_REPO}-oidc}"
ENVIRONMENTS="${ENVIRONMENTS:-dev test prod}"
ROLE_NAME="${ROLE_NAME:-Contributor}"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

az account set --subscription "$SUBSCRIPTION_ID"

echo "▶ Creating Entra app: $APP_NAME"
APP_ID="$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)"

echo "▶ Creating service principal..."
SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
APP_OBJECT_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"

echo "▶ Waiting for propagation..."
sleep 10

echo "▶ Assigning '$ROLE_NAME' at subscription scope..."
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "$ROLE_NAME" \
  --scope "$SCOPE" >/dev/null

_add_fic () {
  local name="$1" subject="$2" description="$3"
  echo "  - ${name}"
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}/federatedIdentityCredentials" \
    --headers "Content-Type=application/json" \
    --body "{
      \"name\": \"${name}\",
      \"issuer\": \"${ISSUER}\",
      \"subject\": \"${subject}\",
      \"description\": \"${description}\",
      \"audiences\": [\"${AUDIENCE}\"]
    }" >/dev/null
}

echo "▶ Creating federated credentials..."
for ENV in $ENVIRONMENTS; do
  _add_fic \
    "github-${GITHUB_REPO}-${ENV}" \
    "repo:${GITHUB_OWNER}/${GITHUB_REPO}:environment:${ENV}" \
    "OIDC for ${GITHUB_REPO} env=${ENV}"
done
_add_fic \
  "github-${GITHUB_REPO}-pr" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:pull_request" \
  "OIDC for ${GITHUB_REPO} pull requests"
_add_fic \
  "github-${GITHUB_REPO}-main" \
  "repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/main" \
  "OIDC for ${GITHUB_REPO} main branch"

cat <<OUT

✅ DONE — App Registration created.

  AZURE_CLIENT_ID=${APP_ID}
  AZURE_TENANT_ID=${TENANT_ID}
  AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}

OUT
