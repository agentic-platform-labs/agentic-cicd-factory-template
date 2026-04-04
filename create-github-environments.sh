#!/usr/bin/env bash
# create-github-environments.sh
# Creates dev / test / prod GitHub Environments.
# prod defaults to the repo owner as required reviewer.
#
# Required env vars:
#   REPO  (format: owner/repo)
# Optional:
#   PROD_REVIEWERS_USERS  (comma-separated GitHub usernames; defaults to repo owner)
#   SKIP_PROD_REVIEWERS   (set to "1" or "true" to skip reviewer configuration entirely)

set -euo pipefail

: "${REPO:?Set REPO=owner/repo}"
PROD_REVIEWERS_USERS="${PROD_REVIEWERS_USERS:-}"
SKIP_PROD_REVIEWERS="${SKIP_PROD_REVIEWERS:-0}"

_create_env() {
  echo "▶ Creating environment: $1"
  local out rc
  out="$(gh api -X PUT "repos/${REPO}/environments/$1" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "  ⚠ Warning: could not create environment '$1': $out"
  fi
}

_set_prod_reviewers() {
  if [[ "$SKIP_PROD_REVIEWERS" == "1" || "$SKIP_PROD_REVIEWERS" == "true" ]]; then
    echo "  ℹ SKIP_PROD_REVIEWERS set — skipping prod reviewer configuration."
    return 0
  fi

  local reviewers_json="[]"
  if [[ -z "$PROD_REVIEWERS_USERS" ]]; then
    PROD_REVIEWERS_USERS="${REPO%%/*}"
  fi

  echo "▶ Setting prod reviewers: $PROD_REVIEWERS_USERS"
  IFS=',' read -ra users <<< "$PROD_REVIEWERS_USERS"
  for u in "${users[@]}"; do
    u="$(echo "$u" | xargs)"
    [[ -z "$u" ]] && continue

    local uid uid_out uid_rc
    uid_out="$(gh api "users/${u}" --jq '.id' 2>&1)"
    uid_rc=$?
    if [[ $uid_rc -ne 0 || -z "$uid_out" ]]; then
      echo "  ⚠ Warning: could not resolve GitHub user ID for '${u}': ${uid_out}"
      echo "    Skipping reviewer '${u}' — set SKIP_PROD_REVIEWERS=1 to suppress this."
      continue
    fi
    uid="$uid_out"
    reviewers_json="$(jq -c --argjson id "$uid" '. + [{"type":"User","reviewer":{"id":$id}}]' <<<"$reviewers_json")"
  done

  if [[ "$(jq 'length' <<<"$reviewers_json")" -eq 0 ]]; then
    echo "  ⚠ Warning: no valid reviewers resolved — prod environment created without approval gate."
    echo "    Configure reviewers manually in Settings → Environments → prod."
    return 0
  fi

  local api_out api_rc
  api_out="$(gh api -X PUT "repos/${REPO}/environments/prod" \
    --input - <<<"$(jq -n --argjson r "$reviewers_json" '{reviewers: $r}')" 2>&1)"
  api_rc=$?
  if [[ $api_rc -ne 0 ]]; then
    echo "  ⚠ Warning: failed to set prod reviewers (exit $api_rc): $api_out"
    echo "    Prod environment exists but has no approval gate."
    echo "    Configure reviewers manually in Settings → Environments → prod."
    echo "    Or re-run with SKIP_PROD_REVIEWERS=1 to silence this warning."
  else
    echo "  ✓ Prod reviewers set."
  fi
}

_create_env dev
_create_env test
_create_env prod
_set_prod_reviewers

echo "✅ DONE — environments dev / test / prod created on $REPO"
