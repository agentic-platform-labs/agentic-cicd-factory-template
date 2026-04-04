# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub Issues.**

Use **Security → Advisories → Report a vulnerability** in this repository,
or contact the maintainer via their GitHub profile.

We aim to acknowledge reports within 72 hours and resolve critical issues within 14 days.

## Scope

- Hardcoded credentials in any committed file
- Insecure defaults in generated workflows or Terraform
- OIDC/authentication misconfigurations

## Important Notice

> ⚠️ This is an **educational template**. It is not production-hardened.
> Review all RBAC assignments, replace placeholder values, and apply your
> organisation's security policy before deploying to shared environments.

## Security Defaults in This Template

- OIDC only — no long-lived secrets stored in GitHub
- `contents: read` at workflow level; `id-token: write` per deploy job only
- All GitHub Actions pinned to full commit SHAs
- Terraform state in Azure Storage with blob-level locking
