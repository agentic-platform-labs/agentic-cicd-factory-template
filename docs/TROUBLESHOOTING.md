# Troubleshooting Guide

Common issues when running the Agentic CI/CD Factory template.

---

## 1. OIDC subject mismatch

**Symptom:**
```
Error: AADSTS70011: The provided request must include a 'scope' input parameter.
AADSTS50146: This application is not configured with a federated identity credential
for the subject 'repo:owner/repo:environment:dev'.
```

**Cause:** The federated credential subject in Entra doesn't match exactly what GitHub sends.

**Fix:**

Check what GitHub actually sent:
- Go to the failed Actions run → expand the OIDC token step
- Look for `subject` in the decoded token

Check what Entra expects:
```bash
APP_ID=$(az ad app list --display-name "${GITHUB_REPO}-oidc" --query "[0].appId" -o tsv)
az ad app federated-credential list --id "$APP_ID" -o table
```

Common mismatches:
| Wrong | Correct |
|-------|---------|
| `repo:Owner/Repo:environment:Dev` | `repo:owner/repo:environment:dev` (case-sensitive) |
| `repo:owner/repo:ref:refs/heads/feature` | Only `main` push has a federated cred; PRs use `pull_request` |
| Missing environment credential | You need one per environment: dev, test, prod |

Re-create the credential:
```bash
az ad app federated-credential delete --id "$APP_ID" --federated-credential-id <ID>
# Then re-run azure-oidc-bootstrap-one-sp.sh or create manually
```

---

## 2. "Expected exactly 1 app registration" error

**Symptom:**
```
ERROR: Expected exactly 1 app registration named 'my-project-oidc', found 0.
```
or
```
ERROR: Expected exactly 1 app registration named 'my-project-oidc', found 2.
```

**Cause (found 0):** The App Registration was just created and Entra hasn't replicated yet.

**Fix:**
```bash
# Wait 30 seconds, then retry
sleep 30
bash onboard-agenticcicd-newrepo.sh
```

**Cause (found 2+):** A previous failed run created a partial registration.

**Fix:**
```bash
# List all apps with this name
az ad app list --display-name "my-project-oidc" --query "[].{Name:displayName, AppId:appId}" -o table

# Delete the duplicate(s)
az ad app delete --id "<duplicate-app-id>"

# Then retry
bash onboard-agenticcicd-newrepo.sh
```

---

## 3. Insufficient permissions for `az ad app list`

**Symptom:**
```
Insufficient privileges to complete the operation.
```
or command returns empty even though an app exists.

**Cause:** Your Azure account doesn't have `Application.Read.All` in Entra.

**Fix options:**

Option A — Use a user account with Application Administrator role in Entra:
```bash
az login                # login as a user with higher Entra permissions
bash onboard-agenticcicd-newrepo.sh
```

Option B — Have an Entra admin run the OIDC bootstrap step:
```bash
# Admin runs this:
bash azure-oidc-bootstrap-one-sp.sh
# Then admin provides the APP_ID (client ID) to you
export AZURE_CLIENT_ID="<provided-by-admin>"
# You continue with the rest:
bash terraform-backend-bootstrap.sh
bash github-secrets-bootstrap.sh
bash create-github-environments.sh
bash branch-protection-main.sh
```

Option C — Use Azure Portal:
- Go to Entra ID → App Registrations → find your app → copy the Application (client) ID
- Manually set: `export AZURE_CLIENT_ID="<copied-id>"`

---

## 4. Missing repo admin for environments / branch protection

**Symptom:**
```
GraphQL: Must have admin rights to Repository. (createEnvironment)
```
or
```
HTTP 403: Must be repository admin to update settings.
```

**Cause:** The `gh` CLI is authenticated as a user without admin access to the repo.

**Fix:**
```bash
# Check who you're logged in as
gh auth status

# Check your repo permissions
gh api repos/${GITHUB_OWNER}/${GITHUB_REPO} --jq '.permissions'
# Must show: "admin": true

# If not admin, re-login as repo owner or request admin access
gh auth logout
gh auth login
```

For organization repos: an org owner or repo admin must either run the script or grant you admin role via **Settings → Collaborators and teams**.

---

## 5. Terraform state lock (concurrent runs)

**Symptom (in CI logs):**
```
Error: Error acquiring the state lock
Lock Info:
  ID:        xxxxxxxx-...
  Operation: OperationTypePlan
```

**Cause:** Two workflow runs tried to access the same Terraform state at the same time.

**Fix:**
- The lock releases automatically when the first run finishes.
- Re-run the failed workflow: `gh run rerun <run-id>`
- If the lock is stuck (e.g., a run was force-cancelled):
```bash
terraform force-unlock -force "<lock-id>"
# Or via Azure Portal: navigate to the blob container, delete the lease on the .tflock blob
```

---

## 6. Storage account name already taken

**Symptom:**
```
The storage account name "sttfstatemyproject" is already taken.
```

**Cause:** Storage account names are globally unique across all of Azure.

**Fix:**
```bash
# Use a unique suffix
export TFSTATE_STORAGE_ACCOUNT="sttfstate$(date +%s | tail -c 6)"
echo "Using: $TFSTATE_STORAGE_ACCOUNT"
bash terraform-backend-bootstrap.sh
bash github-secrets-bootstrap.sh   # re-run to update the variable
```

---

## 7. `gh workflow run` fails — workflow not found

**Symptom:**
```
could not find any workflows named "cd.yml"
```

**Cause:** The workflow file must exist on the default branch (`main`) before it can be dispatched.

**Fix:**
```bash
# Ensure you've pushed your changes
git push origin main

# Verify the workflow is visible
gh workflow list
```

---

## 8. Checkov scan fails on demo Terraform

**Symptom:** CI fails on checkov security scan step.

**Note:** The template uses `soft_fail: true` for checkov, so this should not block CI. If you changed it to `soft_fail: false`, checkov findings will fail the pipeline.

**Fix:**
```bash
# Run checkov locally to see findings
checkov -d infra/envs/dev/ --quiet

# Common findings in demo infra:
# - Storage account: enable HTTPS-only (already enabled in template)
# - Key Vault: purge protection disabled (intentional for lab teardown)
# - Resource group: no locks (intentional for easy cleanup)
```

To suppress a specific finding, add a comment to the Terraform resource:
```hcl
resource "azurerm_key_vault" "kv" {
  # checkov:skip=CKV_AZURE_42:Purge protection intentionally disabled for lab
  purge_protection_enabled = false
}
```
