#!/usr/bin/env python3
"""
contract_lint.py — Runtime guardrails validation.

Validates .github/workflows/*.yml and .github/agents/*.agent.md against
the guardrail policy declared in cicd/contract.yml.

Converts design-time guardrails into enforced CI gates — any drift from the
contract (a new contents:write, an unlisted action registry, a missing
safe_outputs declaration) fails the build immediately.

Usage:
    python scripts/contract_lint.py cicd/contract.yml .github/workflows
    python scripts/contract_lint.py cicd/contract.yml .github/workflows --agents-dir .github/agents

Exits 0 on pass, 1 on violations, 2 on usage/parse errors.
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed.  Run: pip install pyyaml", file=sys.stderr)
    sys.exit(2)


# ─── SHA-pin pattern ─────────────────────────────────────────────────────────

_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


# ─── Result tracking ─────────────────────────────────────────────────────────

_violations: list[str] = []


def _fail(msg: str) -> None:
    _violations.append(msg)
    print(f"  ✗  {msg}")


def _ok(msg: str) -> None:
    print(f"  ✓  {msg}")


# ─── YAML / frontmatter helpers ───────────────────────────────────────────────

def _load_yaml(path: str) -> dict:
    with open(path) as fh:
        return yaml.safe_load(fh) or {}


def _parse_agent_frontmatter(path: str) -> dict:
    """Return the YAML frontmatter block from a Markdown agent definition."""
    content = Path(path).read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return {}
    return yaml.safe_load(match.group(1)) or {}


# ─── Workflow introspection ───────────────────────────────────────────────────

def _collect_permissions(workflow: dict) -> list[tuple[str, str, str]]:
    """
    Return a list of (scope_label, permission_key, value) triples gathered
    from every permissions block in the workflow (top-level and per-job).
    """
    results: list[tuple[str, str, str]] = []
    top = workflow.get("permissions") or {}
    if isinstance(top, dict):
        for k, v in top.items():
            results.append(("workflow-level", k, str(v)))
    for job_name, job in (workflow.get("jobs") or {}).items():
        perms = (job or {}).get("permissions") or {}
        if isinstance(perms, dict):
            for k, v in perms.items():
                results.append((f"job:{job_name}", k, str(v)))
    return results


def _collect_uses(workflow: dict) -> list[str]:
    """Return every `uses:` value found in jobs and steps."""
    uses: list[str] = []
    for _job_name, job in (workflow.get("jobs") or {}).items():
        job = job or {}
        if "uses" in job:
            uses.append(job["uses"])
        for step in job.get("steps") or []:
            if step and "uses" in step:
                uses.append(step["uses"])
    return uses


def _action_org(uses_value: str) -> str | None:
    """Extract the GitHub org from a `uses:` action reference."""
    if uses_value.startswith("./.github/"):
        return None  # local reusable workflow — exempt
    if "@" not in uses_value:
        return None
    ref_part = uses_value.split("@")[0]
    parts = ref_part.split("/")
    return parts[0] if parts else None


def _action_sha(uses_value: str) -> str | None:
    if "@" not in uses_value:
        return None
    return uses_value.split("@", 1)[1]


# ─── Check: contract structure ────────────────────────────────────────────────

def check_contract_structure(contract: dict) -> None:
    print("\n[contract]  cicd/contract.yml — guardrails structure")
    guardrails = contract.get("guardrails") or {}
    if not guardrails:
        _fail("contract.yml is missing the top-level 'guardrails' section")
        return
    for key in ("safe_outputs", "allowed_registries", "agent_permissions", "network"):
        if key in guardrails:
            _ok(f"guardrails.{key} present")
        else:
            _fail(f"contract.yml missing required guardrails.{key}")


# ─── Check: workflow file ─────────────────────────────────────────────────────

def check_workflow(path: str, contract: dict) -> None:
    print(f"\n[workflow]  {path}")
    try:
        wf = _load_yaml(path)
    except Exception as exc:
        _fail(f"Cannot parse {path}: {exc}")
        return

    # Build allowed-orgs set from contract
    allowed_orgs: set[str] = set()
    for entry in (
        contract.get("guardrails", {})
        .get("allowed_registries", {})
        .get("actions") or []
    ):
        # entry format: "github.com/actions" → org "actions"
        allowed_orgs.add(entry.split("/")[-1])

    # 1. Permissions: no contents:write; no broad write permissions at workflow level
    perms_violations = False
    for scope, perm, value in _collect_permissions(wf):
        if perm == "contents" and value == "write":
            _fail(
                f"contents:write at {scope} — violates minimal-permissions guardrail "
                f"(contract: guardrails.agent_permissions.repository_write = false)"
            )
            perms_violations = True
        elif value == "write" and scope == "workflow-level" and perm not in (
            "id-token",
            "contents",
        ):
            _fail(
                f"{perm}:write at workflow-level — must be scoped to the specific job "
                f"that needs it (least-privilege principle)"
            )
            perms_violations = True
    if not perms_violations:
        _ok("No overly-broad permission grants")

    # 2. Action registries and SHA pinning
    registry_ok = True
    pin_ok = True
    for uses in _collect_uses(wf):
        if uses.startswith("./.github/"):
            continue  # local reusable — skip

        org = _action_org(uses)
        sha = _action_sha(uses)

        if org and org not in allowed_orgs:
            _fail(
                f"Action '{uses}' org '{org}' is not in "
                f"guardrails.allowed_registries.actions"
            )
            registry_ok = False

        if sha is None:
            _fail(f"Action '{uses}' has no @pin — all actions must be version-pinned")
            pin_ok = False
        elif not _SHA_RE.match(sha):
            _fail(
                f"Action '{uses}' pinned to '{sha}' — must be a 40-char SHA "
                f"(not a floating tag) to prevent supply-chain drift"
            )
            pin_ok = False

    if registry_ok:
        _ok("All action registries are on the allow-list")
    if pin_ok:
        _ok("All actions are SHA-pinned")


# ─── Check: agent definition ──────────────────────────────────────────────────

def check_agent(path: str) -> None:
    print(f"\n[agent]     {path}")
    fm = _parse_agent_frontmatter(path)
    if not fm:
        _fail(f"{path} has no YAML frontmatter — agent definitions must declare guardrails")
        return
    for key in ("safe_outputs", "network"):
        if key in fm:
            values = fm[key]
            _ok(f"'{key}' declared → {values}")
        else:
            _fail(
                f"'{key}' missing from frontmatter of {path} — "
                f"required by guardrails.agent_permissions policy"
            )


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate GitHub Actions workflows and agent definitions "
        "against cicd/contract.yml guardrails."
    )
    parser.add_argument("contract", help="Path to cicd/contract.yml")
    parser.add_argument("workflows_dir", help="Path to .github/workflows/")
    parser.add_argument(
        "--agents-dir",
        default=".github/agents",
        help="Path to .github/agents/ (default: .github/agents)",
    )
    args = parser.parse_args()

    print("=" * 62)
    print("  Contract Lint — Runtime Guardrails Validation")
    print("=" * 62)

    # Load contract
    try:
        contract = _load_yaml(args.contract)
    except FileNotFoundError:
        print(f"ERROR: contract file not found: {args.contract}", file=sys.stderr)
        sys.exit(2)
    except Exception as exc:
        print(f"ERROR: cannot parse contract: {exc}", file=sys.stderr)
        sys.exit(2)

    # Contract structure
    check_contract_structure(contract)

    # Workflows
    workflow_files = sorted(glob.glob(f"{args.workflows_dir}/*.yml"))
    if not workflow_files:
        _fail(f"No workflow files found in {args.workflows_dir}")
    for wf_path in workflow_files:
        check_workflow(wf_path, contract)

    # Agents
    agent_files = sorted(glob.glob(f"{args.agents_dir}/*.agent.md"))
    if agent_files:
        for agent_path in agent_files:
            check_agent(agent_path)
    else:
        print(f"\n[agents]    No agent files found in {args.agents_dir} — skipping")

    # Summary
    print("\n" + "=" * 62)
    if _violations:
        print(f"  FAILED — {len(_violations)} violation(s) detected:\n")
        for v in _violations:
            print(f"    • {v}")
        print()
        sys.exit(1)
    else:
        print("  PASSED — All guardrail checks passed ✓")
        print()
        sys.exit(0)


if __name__ == "__main__":
    main()
