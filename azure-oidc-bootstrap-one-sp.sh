#!/usr/bin/env bash
# azure-oidc-bootstrap-one-sp.sh
# Creates one Entra App Registration with 5 federated identity credentials
# (one per GitHub Actions trigger: PR, main push, dev/test/prod environments).
#
# Idempotent — safe to re-run:
#   • If an app named ${APP_NAME} already exists, it is reused (not duplicated).
#   • If multiple exist, the script fails with a clear list and exits.
#   • The service principal is created only if it does not already exist.
#   • Federated credentials are created only if not already present (by name).
#   • Role assignment is skipped if it already exists.
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

# ── Step 1: Resolve or create the App Registration ───────────────────────────
echo "▶ Looking up Entra app: $APP_NAME"
EXISTING="$(az ad app list --display-name "$APP_NAME" --query "[].{appId:appId,name:displayName}" -o json)"
COUNT="$(echo "$EXISTING" | jq 'length')"

if [[ "$COUNT" -gt 1 ]]; then
  echo ""
  echo "ERROR: Multiple app registrations found with display name '${APP_NAME}'."
  echo "  Cannot determine which to use. Remove duplicates manually and re-run."
  echo ""
  echo "  Found:"
  echo "$EXISTING" | jq -r '.[] | "    appId=\(.appId)  name=\(.name)"'
  exit 1
elif [[ "$COUNT" -eq 1 ]]; then
  APP_ID="$(echo "$EXISTING" | jq -r '.[0].appId')"
  echo "  ✓ Reusing existing app (appId=$APP_ID)"
else
  echo "  App not found — creating: $APP_NAME"
  APP_ID="$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)"
  echo "  ✓ Created (appId=$APP_ID)"
fi

APP_OBJECT_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"

# ── Step 2: Ensure service principal exists ───────────────────────────────────
echo "▶ Ensuring service principal exists..."
SP_OBJECT_ID="$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)"
if [[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "None" ]]; then
  echo "  Creating service principal..."
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
  echo "  ✓ Created (objectId=$SP_OBJECT_ID)"
  echo "▶ Waiting for propagation..."
  sleep 10
else
  echo "  ✓ Service principal already exists (objectId=$SP_OBJECT_ID)"
fi

# ── Step 3: Role assignment (idempotent) ──────────────────────────────────────
echo "▶ Ensuring '$ROLE_NAME' role assignment at subscription scope..."
SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
EXISTING_RA="$(az role assignment list \
  --assignee "$SP_OBJECT_ID" --role "$ROLE_NAME" --scope "$SCOPE" \
  --query "length(@)" -o tsv 2>/dev/null || echo 0)"
if [[ "$EXISTING_RA" -gt 0 ]]; then
  echo "  ✓ Role assignment already exists — skipping"
else
  az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$ROLE_NAME" \
    --scope "$SCOPE" >/dev/null
  echo "  ✓ Role assigned"
fi

# ── Step 4: Federated credentials (idempotent by name) ────────────────────────
_existing_fic_names() {
  az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}/federatedIdentityCredentials" \
    --query "value[].name" -o json 2>/dev/null | jq -r '.[]' || true
}

_add_fic() {
  local name="$1" subject="$2" description="$3"
  if echo "$EXISTING_FICS" | grep -qx "$name"; then
    echo "  ✓ $name (already exists)"
  else
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
    echo "  + $name (created)"
  fi
}

echo "▶ Ensuring federated credentials..."
EXISTING_FICS="$(_existing_fic_names)"

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

✅ DONE — App Registration ready.

  AZURE_CLIENT_ID=${APP_ID}
  AZURE_TENANT_ID=${TENANT_ID}
  AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}

OUT
