#!/usr/bin/env bash
# create-github-environments.sh
# Creates dev / test / prod GitHub Environments.
# prod defaults to the repo owner as required reviewer.
#
# Required env vars:
#   REPO  (format: owner/repo)
# Optional:
#   PROD_REVIEWERS_USERS  (comma-separated GitHub usernames)

set -euo pipefail

: "${REPO:?Set REPO=owner/repo}"
PROD_REVIEWERS_USERS="${PROD_REVIEWERS_USERS:-}"

_create_env() {
  echo "▶ Creating environment: $1"
  gh api -X PUT "repos/${REPO}/environments/$1" >/dev/null
}

_set_prod_reviewers() {
  local reviewers_json="[]"
  if [[ -z "$PROD_REVIEWERS_USERS" ]]; then
    # Default to repo owner
    PROD_REVIEWERS_USERS="${REPO%%/*}"
  fi
  IFS=',' read -ra users <<< "$PROD_REVIEWERS_USERS"
  for u in "${users[@]}"; do
    u="$(echo "$u" | xargs)"
    [[ -z "$u" ]] && continue
    local uid
    uid="$(gh api "users/${u}" --jq '.id')"
    reviewers_json="$(jq -c --argjson id "$uid" '. + [{"type":"User","reviewer":{"id":$id}}]' <<<"$reviewers_json")"
  done
  if [[ "$(jq 'length' <<<"$reviewers_json")" -gt 0 ]]; then
    echo "▶ Setting prod reviewers: $PROD_REVIEWERS_USERS"
    gh api -X PUT "repos/${REPO}/environments/prod" \
      --input - <<< "{\"reviewers\": $(echo "$reviewers_json")}" >/dev/null
  fi
}

_create_env dev
_create_env test
_create_env prod
_set_prod_reviewers

echo "✅ DONE — environments dev / test / prod created on $REPO"
