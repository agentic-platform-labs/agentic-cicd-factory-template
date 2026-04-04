# Agentic CI/CD Factory — Enterprise Template

[![CI](https://github.com/dhineshkumarganesan/agentic-cicd-factory-template/actions/workflows/ci.yml/badge.svg)](https://github.com/dhineshkumarganesan/agentic-cicd-factory-template/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OIDC Auth](https://img.shields.io/badge/Auth-OIDC%20only-green)](docs/ONBOARDING.md)
[![No Secrets](https://img.shields.io/badge/Secrets-Zero%20hardcoded-green)](SECURITY.md)

## What it is

A **production-pattern CI/CD factory template** that any team can fork to provision Azure infrastructure through GitHub Actions + Terraform + OIDC. Resources are scaffolded on demand using built-in Copilot agents — no manual Terraform authoring required.

Built on:

- **GitHub Actions** — CI (lint, validate, plan all envs), CD (progressive dev → test → prod), Destroy
- **Terraform** — Remote state on Azure Blob Storage, OIDC auth (no stored secrets)
- **Azure** — Any resource type scaffolded via `@terraform-module-expert` Copilot agent
- **Agentic patterns** — safe-outputs, minimal permissions, SHA-pinned actions, job-level OIDC
- **Copilot agents + skills** — terraform-module-expert, terraform-security, azure-architecture-reviewer

## Getting started

Review and customize Terraform variables, RBAC assignments, and naming conventions for your organization before deploying to production.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| `az` CLI | ≥ 2.55 | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `gh` CLI | ≥ 2.40 | https://cli.github.com |
| `jq` | ≥ 1.6 | `brew install jq` / `apt install jq` |
| `terraform` | ≥ 1.6 | https://developer.hashicorp.com/terraform/install |

**Azure permissions required:**
- Create App Registrations (Entra)
- Create Service Principals
- `Owner` or `Contributor` + `User Access Administrator` on the target subscription

**GitHub permissions required:**
- Repo admin (to set secrets, variables, branch protection, environments)
- GitHub Free plan is sufficient

---

## Tomorrow Runbook (quick start)

### 1. Use this template

```bash
gh repo create my-project --template dhineshkumarganesan/agentic-cicd-factory-template --public
gh repo clone my-project && cd my-project
```

### 2. Patch Terraform state keys

```bash
export STATE_PREFIX="my-project"
bash setup/patch-tfstate-keys.sh
git add .github/workflows/ && git commit -m "chore: patch tfstate keys for my-project"
```

### 3. Export required env vars

```bash
export SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export LOCATION="eastus"
export GITHUB_OWNER="your-github-username"
export GITHUB_REPO="my-project"
export TFSTATE_RESOURCE_GROUP="rg-tfstate-my-project"
export TFSTATE_STORAGE_ACCOUNT="sttfstatemyproject"    # globally unique, 3-24 chars
export TFSTATE_CONTAINER="tfstate"
```

### 4. Run onboarding

```bash
bash setup/onboard-agenticcicd-newrepo.sh
```

This single script:
- Creates an Entra App Registration with 5 OIDC federated credentials
- Creates the Terraform state storage backend
- Sets GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)
- Sets GitHub variables (`TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`)
- Creates GitHub Environments (`dev`, `test`, `prod` — prod requires approval)
- Applies branch protection on `main`

### 5. Push and trigger CD

```bash
git push origin main
gh workflow run cd.yml -f environment=dev
gh run watch
```

### 6. Verify deployment

```bash
# Get website URL from Terraform outputs
gh run view --log | grep website_endpoint
# Or: az storage account show-connection-string ...
```

### 7. Cleanup

```bash
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"
bash setup/cleanup-lab.sh
```

---

## Repo structure

```
.
├── .github/workflows/
│   ├── ci.yml                        # PR validation: lint, scan, plan
│   ├── cd.yml                        # Deploy: dev → test → prod
│   ├── destroy.yml                   # Destroy (manual trigger, gated)
│   ├── _reusable-tf-ci.yml           # Reusable: TF fmt/validate/plan
│   ├── _reusable-deploy-azure-tf.yml # Reusable: TF apply with OIDC
│   └── _reusable-destroy-azure-tf.yml# Reusable: TF destroy with OIDC
├── infra/envs/dev/
│   ├── main.tf                       # RG + Storage Website + Key Vault
│   ├── variables.tf
│   └── outputs.tf
├── docs/
│   ├── ONBOARDING.md                 # Detailed onboarding walkthrough
│   └── TROUBLESHOOTING.md            # Common issues and fixes
├── azure-oidc-bootstrap-one-sp.sh    # Create Entra App + OIDC creds
├── terraform-backend-bootstrap.sh    # Create TF state storage
├── github-secrets-bootstrap.sh       # Set GitHub secrets + variables
├── create-github-environments.sh     # Create dev/test/prod environments
├── branch-protection-main.sh         # Apply main branch protection
├── onboard-agenticcicd-newrepo.sh    # ← Start here (runs all above)
├── patch-tfstate-keys.sh             # Rename TF state key paths
├── cleanup-lab.sh                    # Destroy all lab resources
├── .gitignore
├── LICENSE
└── SECURITY.md
```

---

## Security defaults

| Principle | Implementation |
|-----------|---------------|
| No long-lived secrets | OIDC only (`id-token: write` per-job) |
| Minimal permissions | `contents: read` default; `write` never at workflow level |
| SHA-pinned actions | All `uses:` references pinned to commit SHAs |
| No hardcoded IDs | All Azure IDs via GitHub Secrets/Variables |
| State encryption | Azure Storage Server-Side Encryption (default) |
| KV RBAC enabled | No vault access policy model — RBAC only |

---

## License

MIT — see [LICENSE](LICENSE).  
Not affiliated with Microsoft or GitHub.
