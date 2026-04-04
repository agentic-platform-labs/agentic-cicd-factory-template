#!/usr/bin/env bash
# terraform-backend-bootstrap.sh
# Creates Azure Storage Account for Terraform remote state with blob locking.
#
# Required env vars:
#   SUBSCRIPTION_ID, LOCATION
#   TFSTATE_RG  (or TFSTATE_RESOURCE_GROUP — both accepted)
#   TFSTATE_STORAGE_ACCOUNT  (globally unique, 3-24 lowercase chars)
#   TFSTATE_CONTAINER
#   AZURE_CLIENT_ID  (service principal client ID for RBAC assignment)

set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID}"
: "${LOCATION:?Set LOCATION}"
: "${TFSTATE_STORAGE_ACCOUNT:?Set TFSTATE_STORAGE_ACCOUNT}"
: "${TFSTATE_CONTAINER:?Set TFSTATE_CONTAINER}"
: "${AZURE_CLIENT_ID:?Set AZURE_CLIENT_ID}"

# Accept either TFSTATE_RG or TFSTATE_RESOURCE_GROUP
TFSTATE_RG="${TFSTATE_RG:-${TFSTATE_RESOURCE_GROUP:-}}"
: "${TFSTATE_RG:?Set TFSTATE_RG or TFSTATE_RESOURCE_GROUP}"

TFSTATE_SKU="${TFSTATE_SKU:-Standard_LRS}"

az account set --subscription "$SUBSCRIPTION_ID"

echo "▶ Creating resource group: $TFSTATE_RG"
az group create -n "$TFSTATE_RG" -l "$LOCATION" 1>/dev/null

echo "▶ Creating storage account: $TFSTATE_STORAGE_ACCOUNT"
set +e
OUT=$(az storage account create \
  -n "$TFSTATE_STORAGE_ACCOUNT" \
  -g "$TFSTATE_RG" \
  -l "$LOCATION" \
  --sku "$TFSTATE_SKU" \
  --kind StorageV2 2>&1)
RC=$?
set -e
if [[ $RC -ne 0 ]]; then
  echo "$OUT" | grep -qiE "AlreadyExists|Conflict" && echo "  (already exists — continuing)" || { echo "$OUT" >&2; exit $RC; }
fi

echo "▶ Creating container: $TFSTATE_CONTAINER"
az storage container create \
  --name "$TFSTATE_CONTAINER" \
  --account-name "$TFSTATE_STORAGE_ACCOUNT" \
  --auth-mode login 1>/dev/null

echo "▶ Assigning 'Storage Blob Data Contributor' to service principal..."
SCOPE=$(az storage account show -n "$TFSTATE_STORAGE_ACCOUNT" -g "$TFSTATE_RG" --query id -o tsv)
set +e
RBAC_OUT=$(az role assignment create \
  --assignee "$AZURE_CLIENT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$SCOPE" 2>&1)
RBAC_RC=$?
set -e
if [[ $RBAC_RC -ne 0 ]]; then
  echo "$RBAC_OUT" | grep -qiE "RoleAssignmentExists" && echo "  (already exists — continuing)" || { echo "$RBAC_OUT" >&2; exit $RBAC_RC; }
fi

echo ""
echo "✅ DONE — Terraform backend ready."
echo "  TFSTATE_RESOURCE_GROUP=$TFSTATE_RG"
echo "  TFSTATE_STORAGE_ACCOUNT=$TFSTATE_STORAGE_ACCOUNT"
echo "  TFSTATE_CONTAINER=$TFSTATE_CONTAINER"
