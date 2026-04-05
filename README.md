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
export GITHUB_OWNER="your-github-username"   # ⚠️ exact case — critical for OIDC
export GITHUB_REPO="my-project"
export TFSTATE_RESOURCE_GROUP="rg-tfstate-my-project"
export TFSTATE_STORAGE_ACCOUNT="sttfstatemyproject"    # globally unique, 3-24 chars
export TFSTATE_CONTAINER="tfstate"
```

### 4. Run setup — one script per step

```bash
# Step 1: Create Entra App Registration + 5 OIDC federated credentials
bash setup/azure-oidc-bootstrap-one-sp.sh
# ↳ prints AZURE_CLIENT_ID — export it before proceeding:
export AZURE_CLIENT_ID="<value printed above>"

# Step 2: Create Terraform state storage backend
bash setup/terraform-backend-bootstrap.sh

# Step 3: Set GitHub secrets and variables
export REPO="${GITHUB_OWNER}/${GITHUB_REPO}"
export AZURE_TENANT_ID="$TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
bash setup/github-secrets-bootstrap.sh

# Step 4: Create dev / test / prod GitHub Environments
export PROD_REVIEWERS_USERS="your-github-username"
bash setup/create-github-environments.sh

# Step 5: Apply branch protection on main
bash setup/branch-protection-main.sh
```

> See [docs/ONBOARDING.md](docs/ONBOARDING.md) for the full walkthrough with explanations.

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
export RUN_DESTROY_WORKFLOW=true
export ENVIRONMENT=all
bash setup/cleanup-lab.sh
```

---

## Repo structure

```
.
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                         # PR validation: lint, scan, plan (all 3 envs)
│   │   ├── cd.yml                         # Deploy: dev → test → prod
│   │   ├── destroy.yml                    # Destroy (manual trigger, gated)
│   │   ├── _reusable-tf-ci.yml            # Reusable: TF fmt/validate/plan
│   │   ├── _reusable-deploy-azure-tf.yml  # Reusable: TF apply with OIDC
│   │   └── _reusable-destroy-azure-tf.yml # Reusable: TF destroy with OIDC
│   ├── agents/
│   │   ├── terraform-module-expert.agent.md    # Scaffold any Azure resource
│   │   ├── terraform-coordinator.agent.md      # Routes between agents
│   │   ├── terraform-security.agent.md         # Security review
│   │   ├── azure-architecture-reviewer.agent.md# WAF/CAF compliance
│   │   └── terraform-provider-upgrade.agent.md # Safe provider upgrades
│   ├── skills/
│   │   ├── azure-verified-modules/        # AVM reference patterns
│   │   ├── azure-architecture-review/     # Architecture review patterns
│   │   ├── github-actions-terraform/      # CI/CD pipeline patterns
│   │   ├── terraform-provider-upgrade/    # Provider upgrade patterns
│   │   ├── terraform-security-scan/       # Security scan patterns
│   │   └── drawio-mcp-diagramming/        # Architecture diagram generation
│   └── copilot-instructions.md            # Azure architecture guidance for Copilot
├── infra/
│   └── envs/
│       ├── dev/                           # Development environment
│       │   ├── main.tf                    # Resources scaffolded via @terraform-module-expert
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── test/                          # Test environment
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── prod/                          # Production environment
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── cicd/
│   └── contract.yml                       # Pipeline guardrails declaration
├── scripts/
│   └── contract_lint.py                   # Validates contract.yml in CI
├── setup/                                 # ← Run these to onboard a new repo
│   ├── fix-oidc-subjects.sh               # OIDC repair tool (run if CI fails with AADSTS700213)
│   ├── azure-oidc-bootstrap-one-sp.sh     # Create Entra App + OIDC creds
│   ├── terraform-backend-bootstrap.sh     # Create TF state storage
│   ├── github-secrets-bootstrap.sh        # Set GitHub secrets + variables
│   ├── create-github-environments.sh      # Create dev/test/prod environments
│   ├── branch-protection-main.sh          # Apply main branch protection
│   ├── patch-tfstate-keys.sh              # Rename TF state key paths
│   └── cleanup-lab.sh                     # Destroy all resources
├── docs/
│   ├── ONBOARDING.md                      # Detailed onboarding walkthrough
│   └── TROUBLESHOOTING.md                 # Common issues and fixes
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
