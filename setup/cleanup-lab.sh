#!/usr/bin/env bash
# cleanup-lab.sh
# Destroys all Azure resources created by this lab template.
# Optionally triggers the GitHub Actions destroy workflow first.
#
# Required env vars:
#   REPO                   — format: owner/repo
#   SUBSCRIPTION_ID        — Azure subscription ID
#   TFSTATE_RESOURCE_GROUP — resource group containing the tfstate storage account
#
# Optional env vars:
#   RUN_DESTROY_WORKFLOW   — "true" to trigger destroy.yml via GitHub Actions first
#   ENVIRONMENT            — environment to destroy via workflow (default: all)

set -euo pipefail

: "${REPO:?Set REPO=owner/repo}"
: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${TFSTATE_RESOURCE_GROUP:?Set TFSTATE_RESOURCE_GROUP}"

RUN_DESTROY_WORKFLOW="${RUN_DESTROY_WORKFLOW:-false}"
ENVIRONMENT="${ENVIRONMENT:-all}"

echo "═══════════════════════════════════════════════════════"
echo "  Agentic CI/CD Factory — Lab Cleanup"
echo "  Repo:              ${REPO}"
echo "  Subscription:      ${SUBSCRIPTION_ID}"
echo "  TFState RG:        ${TFSTATE_RESOURCE_GROUP}"
echo "  Destroy workflow:  ${RUN_DESTROY_WORKFLOW}"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Optional: trigger GitHub Actions destroy workflow ─────────────────────────
if [[ "$RUN_DESTROY_WORKFLOW" == "true" ]]; then
  echo "▶ Triggering destroy workflow (environment: ${ENVIRONMENT})..."
  gh workflow run destroy.yml \
    -R "$REPO" \
    -f environment="${ENVIRONMENT}" \
    -f confirm="DESTROY"
  echo "  Waiting for destroy workflow to complete..."
  sleep 15
  # Wait for the run to finish (up to 15 minutes)
  RUN_ID=$(gh run list -R "$REPO" --workflow=destroy.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$RUN_ID" -R "$REPO" --exit-status || {
    echo "⚠ Destroy workflow did not complete successfully. Continuing with RG deletion..."
  }
fi

# ── Delete the Terraform state resource group (removes storage + all state) ──
echo ""
echo "▶ Deleting resource group: ${TFSTATE_RESOURCE_GROUP}"
echo "  (This deletes the Terraform state storage account and all state files)"
echo ""
read -rp "  Type 'yes' to confirm deletion: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted — no resources deleted."
  exit 0
fi

az account set --subscription "$SUBSCRIPTION_ID"
az group delete --name "$TFSTATE_RESOURCE_GROUP" --yes --no-wait
echo "  Deletion submitted (async). Waiting for completion..."
az group wait --name "$TFSTATE_RESOURCE_GROUP" --deleted --timeout 600 || \
  echo "⚠ Wait timed out — check Azure portal to confirm deletion."

echo ""
echo "✅ DONE — lab cleanup complete."
echo ""
echo "  Remaining cleanup (manual):"
echo "    • Delete the Entra App Registration if no longer needed:"
echo "      az ad app delete --id <APP_CLIENT_ID>"
echo "    • Remove GitHub Environments from repo settings if desired."
