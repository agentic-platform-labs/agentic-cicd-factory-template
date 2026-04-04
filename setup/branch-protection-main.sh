#!/usr/bin/env bash
# branch-protection-main.sh
# Applies branch protection to main: requires PR + all CI status checks.
#
# Required env vars:
#   REPO  (format: owner/repo)

set -euo pipefail

: "${REPO:?Set REPO=owner/repo}"
BRANCH="${BRANCH:-main}"

CHECKS='["IaC Security Scan","Generate SBOM","Terraform CI (fmt / validate / plan)"]'

echo "▶ Applying branch protection to ${REPO}:${BRANCH}"
gh api -X PUT "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ${CHECKS}
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
JSON

echo "✅ DONE — branch protection set on ${BRANCH}"
