# Onboarding Guide

Detailed walkthrough for running the Agentic CI/CD Factory template end-to-end.

> **Tip:** Read through this once before running anything.
> The [README](../README.md) has the quick-start. This doc has the *why* behind each step.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Create your repo from template](#1-create-your-repo-from-template)
3. [Clone and patch state keys](#2-clone-and-patch-tfstate-keys)
4. [Set environment variables](#3-set-environment-variables)
5. [Run onboarding](#4-run-onboarding-script)
6. [What the onboarding script does](#what-the-onboarding-script-does)
7. [Trigger CI](#5-trigger-ci)
8. [Trigger CD (deploy)](#6-trigger-cd)
9. [Verify the deployment](#7-verify-the-deployment)
10. [Cleanup](#8-cleanup)

---

## Prerequisites

Before starting, ensure all tools are installed and you are authenticated:

```bash
# Check versions
az version
gh --version
jq --version
terraform version

# Login
az login
az account set --subscription "$SUBSCRIPTION_ID"
gh auth login
```

**Azure permissions you need:**
- `Owner` or `Contributor + User Access Administrator` on the subscription
- Ability to create Entra App Registrations (Application Administrator or equivalent)

**GitHub permissions you need:**
- Repository admin (to set secrets, environments, branch protection)

---

## 1. Create your repo from template

Using the GitHub web UI:
1. Go to https://github.com/dhineshkumarganesan/agentic-cicd-factory-template
2. Click **Use this template → Create a new repository**
3. Name your repo, choose public/private, click **Create**

Or via CLI:
```bash
gh repo create my-project \
  --template dhineshkumarganesan/agentic-cicd-factory-template \
  --public
```

Clone it locally:
```bash
gh repo clone my-project
cd my-project
```

---

## 2. Clone and patch tfstate keys

The workflow files reference `agentic-cicd-factory-template/` as the Terraform state key prefix.
You need to replace this with your own repo name so state files don't collide.

```bash
export STATE_PREFIX="my-project"    # use your actual repo name
export DRY_RUN=true                 # preview first
bash patch-tfstate-keys.sh

# If the diff looks correct:
export DRY_RUN=false
bash patch-tfstate-keys.sh

# Commit
git add .github/workflows/
git commit -m "chore: patch tfstate keys for my-project"
```

**What changes:** Lines like `tf_state_key: "agentic-cicd-factory-template/dev.terraform.tfstate"` become `tf_state_key: "my-project/dev.terraform.tfstate"`.

---

## 3. Set environment variables

Export all required variables before running the onboarding script:

```bash
# Azure identifiers
export SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export LOCATION="eastus"                    # any valid Azure region

# GitHub identifiers
export GITHUB_OWNER="your-github-username"  # or org name
export GITHUB_REPO="my-project"             # just the repo name, no owner prefix

# Terraform state backend
export TFSTATE_RESOURCE_GROUP="rg-tfstate-my-project"
export TFSTATE_STORAGE_ACCOUNT="sttfstatemyproject"  # 3-24 lowercase chars, globally unique
export TFSTATE_CONTAINER="tfstate"

# Optional: override which GitHub users approve prod deployments
# export PROD_REVIEWERS_USERS="alice,bob"   # defaults to repo owner
```

**Finding your IDs:**
```bash
# Subscription ID
az account show --query id -o tsv

# Tenant ID
az account show --query tenantId -o tsv
```

---

## 4. Run onboarding script

```bash
bash onboard-agenticcicd-newrepo.sh
```

This takes about 2–3 minutes. See the next section for what it does.

---

## What the onboarding script does

| Step | What happens |
|------|-------------|
| 1. OIDC bootstrap | Creates one Entra App Registration (`${GITHUB_REPO}-oidc`) with 5 federated identity credentials — one for each GitHub Actions context: PR, main push, dev env, test env, prod env |
| 2. Resolve Client ID | Looks up the newly created app by name; fails if not exactly 1 match (prevents ambiguity) |
| 3. TF backend | Creates the Resource Group and Storage Account for Terraform remote state; assigns `Storage Blob Data Contributor` to the service principal |
| 4. GitHub secrets | Sets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` as encrypted repo secrets |
| 5. GitHub variables | Sets `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER` as repo variables |
| 6. Environments | Creates `dev`, `test`, `prod` GitHub Environments; prod requires reviewer approval |
| 7. Branch protection | Requires PR + all CI checks on `main`; enforces for admins too |

---

## 5. Trigger CI

Push any change to trigger CI, or trigger manually:

```bash
# Manual dispatch
gh workflow run ci.yml

# Watch
gh run watch
```

CI runs: IaC security scan (checkov) → Terraform fmt/validate/plan (all 3 environments).

---

## 6. Trigger CD

CD deploys dev → test → prod in sequence. Prod requires a manual approval from the configured reviewer.

```bash
# Deploy dev only
gh workflow run cd.yml -f environment=dev

# Deploy all (dev → test → prod)
gh workflow run cd.yml -f environment=all

# Watch progress
gh run watch
```

---

## 7. Verify the deployment

After CD succeeds, retrieve the outputs:

```bash
# From Terraform outputs (via workflow logs)
gh run view --log | grep -E "website_endpoint|key_vault"

# Or directly from Azure
az storage account show \
  -n "your-storage-account-name" \
  -g "your-resource-group-name" \
  --query "primaryEndpoints.web" -o tsv
```

Open the static website endpoint in your browser — you'll see the index.html.

---

## 8. Cleanup

When done with the lab, destroy all Azure resources:

```bash
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"
export SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TFSTATE_RESOURCE_GROUP="rg-tfstate-my-project"

# Option A: just delete the state RG (fastest)
bash cleanup-lab.sh

# Option B: trigger GitHub Actions destroy workflow first, then delete state RG
export RUN_DESTROY_WORKFLOW=true
bash cleanup-lab.sh
```

After cleanup, optionally remove the Entra App Registration:
```bash
APP_ID=$(az ad app list --display-name "${GITHUB_REPO}-oidc" --query "[0].appId" -o tsv)
az ad app delete --id "$APP_ID"
```
