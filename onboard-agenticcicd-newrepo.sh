#!/usr/bin/env bash
# onboard-agenticcicd-newrepo.sh
# Single-script onboarding for agentic-cicd-factory-template.
# Runs all bootstrap steps in order and prints a success summary.
#
# Required env vars:
#   SUBSCRIPTION_ID       — Azure subscription ID
#   TENANT_ID             — Azure tenant ID
#   LOCATION              — Azure region (e.g. eastus)
#   GITHUB_OWNER          — GitHub username or org
#   GITHUB_REPO           — GitHub repository name (no owner prefix)
#   TFSTATE_RESOURCE_GROUP — Resource group for Terraform state storage
#   TFSTATE_STORAGE_ACCOUNT — Storage account name (globally unique, 3-24 chars)
#   TFSTATE_CONTAINER      — Blob container name (e.g. tfstate)
#
# Optional env vars:
#   PROD_REVIEWERS_USERS  — comma-separated GitHub usernames for prod approval
#                           (defaults to repo owner)
#   APP_NAME              — Entra app display name (default: ${GITHUB_REPO}-oidc)
#   ENVIRONMENTS          — space-separated list (default: "dev test prod")

set -euo pipefail

# ── Required env var validation ───────────────────────────────────────────────
_require() { [[ -n "${!1:-}" ]] || { echo "ERROR: $1 is required"; exit 1; }; }
_require SUBSCRIPTION_ID
_require TENANT_ID
_require LOCATION
_require GITHUB_OWNER
_require GITHUB_REPO
_require TFSTATE_RESOURCE_GROUP
_require TFSTATE_STORAGE_ACCOUNT
_require TFSTATE_CONTAINER

# Compatibility alias — both names work
export TFSTATE_RG="$TFSTATE_RESOURCE_GROUP"
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "═══════════════════════════════════════════════════════"
echo "  Agentic CI/CD Factory — Onboarding"
echo "  Repo:     ${REPO}"
echo "  Location: ${LOCATION}"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Step 1: OIDC App Registration ────────────────────────────────────────────
echo "──── Step 1/5: Azure OIDC App Registration ────"
export APP_NAME="${APP_NAME:-${GITHUB_REPO}-oidc}"
bash "${SCRIPT_DIR}/azure-oidc-bootstrap-one-sp.sh"

# ── Step 2: Resolve AZURE_CLIENT_ID ──────────────────────────────────────────
echo "──── Step 2/5: Resolving AZURE_CLIENT_ID ────"
MATCHES=$(az ad app list --display-name "$APP_NAME" --query "[].appId" -o tsv)
COUNT=$(echo "$MATCHES" | grep -c . || true)
if [[ "$COUNT" -ne 1 ]]; then
  echo "ERROR: Expected exactly 1 app registration named '$APP_NAME', found $COUNT."
  echo "  If 0: wait 30s and retry. If >1: delete duplicates manually."
  exit 1
fi
export AZURE_CLIENT_ID="$MATCHES"
export AZURE_TENANT_ID="$TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
echo "  AZURE_CLIENT_ID=$AZURE_CLIENT_ID ✓"

# ── Step 3: Terraform state backend ─────────────────────────────────────────
echo "──── Step 3/5: Terraform Backend ────"
bash "${SCRIPT_DIR}/terraform-backend-bootstrap.sh"

# ── Step 4: GitHub secrets + variables ───────────────────────────────────────
echo "──── Step 4/5: GitHub Secrets & Variables ────"
bash "${SCRIPT_DIR}/github-secrets-bootstrap.sh"

# ── Step 5: GitHub Environments + Branch Protection ──────────────────────────
echo "──── Step 5/5: GitHub Environments & Branch Protection ────"
bash "${SCRIPT_DIR}/create-github-environments.sh"
bash "${SCRIPT_DIR}/branch-protection-main.sh"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Onboarding complete!"
echo ""
echo "  Azure:"
echo "    Client ID:       $AZURE_CLIENT_ID"
echo "    Subscription:    $SUBSCRIPTION_ID"
echo "    State backend:   $TFSTATE_STORAGE_ACCOUNT / $TFSTATE_CONTAINER"
echo ""
echo "  GitHub:"
echo "    Repo:            https://github.com/${REPO}"
echo "    Environments:    dev / test / prod (prod: approval required)"
echo "    Branch protect:  main (PR required + CI checks)"
echo ""
echo "  Next steps:"
echo "    1. Patch tfstate keys:  bash patch-tfstate-keys.sh"
echo "    2. Push to main:        git push origin main"
echo "    3. Open a PR:           gh pr create"
echo "    4. Watch CI:            gh run watch"
echo "═══════════════════════════════════════════════════════"
