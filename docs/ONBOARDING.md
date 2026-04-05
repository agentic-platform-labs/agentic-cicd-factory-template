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
5. [Step 1 — Create Entra App + OIDC credentials](#4-step-1--create-entra-app--oidc-credentials)
6. [Step 2 — Create Terraform state backend](#5-step-2--create-terraform-state-backend)
7. [Step 3 — Set GitHub secrets & variables](#6-step-3--set-github-secrets--variables)
8. [Step 4 — Create GitHub environments](#7-step-4--create-github-environments)
9. [Step 5 — Apply branch protection](#8-step-5--apply-branch-protection)
10. [Trigger CI](#9-trigger-ci)
11. [Trigger CD (deploy)](#10-trigger-cd)
12. [Verify the deployment](#11-verify-the-deployment)
13. [Cleanup](#12-cleanup)

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
1. Go to https://github.com/agentic-platform-labs/agentic-cicd-factory-template
2. Click **Use this template → Create a new repository**
3. Name your repo, choose public/private, click **Create**

Or via CLI:
```bash
gh repo create my-project \
  --template agentic-platform-labs/agentic-cicd-factory-template \
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
bash setup/patch-tfstate-keys.sh

# If the diff looks correct:
export DRY_RUN=false
bash setup/patch-tfstate-keys.sh

# Commit
git add .github/workflows/
git commit -m "chore: patch tfstate keys for my-project"
```

**What changes:** Lines like `tf_state_key: "agentic-cicd-factory-template/dev.terraform.tfstate"` become `tf_state_key: "my-project/dev.terraform.tfstate"`.

---

## 3. Set environment variables

Export these variables before running the setup steps. Keep this terminal session open — you will reuse these values across all steps.

```bash
# Azure identifiers
export SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export LOCATION="eastus"                    # any valid Azure region

# GitHub identifiers — ⚠️ GITHUB_OWNER must match EXACT case shown in GitHub URL
export GITHUB_OWNER="your-github-username"  # or org name, exact case
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
az account show --query id -o tsv          # Subscription ID
az account show --query tenantId -o tsv    # Tenant ID
```

---

## 4. Step 1 — Create Entra App + OIDC credentials

```bash
bash setup/azure-oidc-bootstrap-one-sp.sh
```

**What it does:** Creates one Entra App Registration (`${GITHUB_REPO}-oidc`) with 5 federated identity credentials — one for each GitHub Actions context: PR, main push, dev/test/prod environments.

**Output:** Prints `AZURE_CLIENT_ID=...` — **copy this value and export it immediately**:

```bash
export AZURE_CLIENT_ID="<value printed above>"
```

> ⚠️ **Critical:** `GITHUB_OWNER` must be set with the exact case from your GitHub URL (e.g., `MyOrg` not `myorg`). Azure AD subject matching is case-sensitive — a mismatch here causes OIDC failures later.

---

## 5. Step 2 — Create Terraform state backend

```bash
bash setup/terraform-backend-bootstrap.sh
```

**What it does:** Creates the Resource Group and Storage Account for Terraform remote state; assigns `Storage Blob Data Contributor` to the service principal.

Requires: `SUBSCRIPTION_ID`, `LOCATION`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`, `AZURE_CLIENT_ID` (from Step 1).

---

## 6. Step 3 — Set GitHub secrets & variables

```bash
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"
export AZURE_TENANT_ID="$TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

bash setup/github-secrets-bootstrap.sh
```

**What it does:** Sets 3 GitHub repo secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and 3 repo variables (`TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`).

---

## 7. Step 4 — Create GitHub environments

```bash
export PROD_REVIEWERS_USERS="your-github-username"  # prod approval gate

bash setup/create-github-environments.sh
```

**What it does:** Creates `dev`, `test`, `prod` GitHub Environments. The prod environment requires a manual reviewer approval before CD proceeds.

---

## 8. Step 5 — Apply branch protection

```bash
bash setup/branch-protection-main.sh
```

**What it does:** Requires a PR and all CI checks to pass before merging to `main`. Enforced for admins too.

---

## 9. Trigger CI

Push any change to trigger CI, or trigger manually:

```bash
# Manual dispatch
gh workflow run ci.yml

# Watch
gh run watch
```

CI runs: IaC security scan (checkov) → Terraform fmt/validate/plan (all 3 environments).

---

## 10. Trigger CD

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

## 11. Verify the deployment

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

## 12. Cleanup

When you need to destroy all Azure resources:

```bash
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"
export SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TFSTATE_RESOURCE_GROUP="rg-tfstate-my-project"
export RUN_DESTROY_WORKFLOW=true
export ENVIRONMENT=all

bash setup/cleanup-lab.sh
```

> The Entra App Registration and GitHub Environments are intentionally **not** deleted by cleanup — they are free to keep and reuse for the next lab run.

If OIDC breaks after cleanup and re-setup, repair it with:
```bash
export AZURE_CLIENT_ID="<your-client-id>"
export GITHUB_OWNER="your-github-username"
export GITHUB_REPO="my-project"
bash setup/fix-oidc-subjects.sh
# Wait 2 minutes, then re-run CI
```
