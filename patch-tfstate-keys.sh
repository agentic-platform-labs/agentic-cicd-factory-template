#!/usr/bin/env bash
# patch-tfstate-keys.sh
# Safely replaces the Terraform state key prefix in workflow YAML files.
#
# Use this after forking/cloning the template to rename the state paths
# from the default "agentic-cicd-factory-template/" to your repo name.
#
# Required env vars:
#   STATE_PREFIX    — new prefix to use (e.g. "my-project")
#
# Optional env vars:
#   WORKFLOW_FILES  — glob pattern (default: .github/workflows/*.yml)
#   DRY_RUN         — set to "true" to show diff without writing (default: false)
#
# Example:
#   export STATE_PREFIX="my-new-repo"
#   bash patch-tfstate-keys.sh

set -euo pipefail

: "${STATE_PREFIX:?Set STATE_PREFIX to your repo name (e.g. my-project)}"

WORKFLOW_FILES="${WORKFLOW_FILES:-.github/workflows/*.yml}"
DRY_RUN="${DRY_RUN:-false}"

OLD_PREFIX="agentic-cicd-factory-template"

echo "▶ Patching tfstate keys: '${OLD_PREFIX}/' → '${STATE_PREFIX}/'"
echo "  Files: ${WORKFLOW_FILES}"
echo ""

changed=0
for f in $WORKFLOW_FILES; do
  [[ -f "$f" ]] || continue
  if grep -q "${OLD_PREFIX}/" "$f"; then
    echo "  → $f"
    if [[ "$DRY_RUN" == "true" ]]; then
      grep -n "${OLD_PREFIX}/" "$f" | sed "s/^/    [dry-run] /"
    else
      # In-place replacement (BSD and GNU sed compatible via temp file)
      sed "s|${OLD_PREFIX}/|${STATE_PREFIX}/|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      grep "tf_state_key" "$f" | sed "s/^/    ✓ /"
    fi
    changed=$((changed + 1))
  fi
done

echo ""
if [[ $changed -eq 0 ]]; then
  echo "  No files contained '${OLD_PREFIX}/' — nothing changed."
  echo "  (Already patched, or STATE_PREFIX is already set correctly)"
elif [[ "$DRY_RUN" == "true" ]]; then
  echo "  DRY_RUN=true — no files written. Re-run without DRY_RUN to apply."
else
  echo "✅ DONE — patched $changed file(s)."
  echo "  Review changes: git diff .github/workflows/"
  echo "  Commit:         git add .github/workflows/ && git commit -m 'chore: patch tfstate keys for ${STATE_PREFIX}'"
fi
