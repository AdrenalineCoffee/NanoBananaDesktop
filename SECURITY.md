# Security Policy

## Supported versions
Security fixes are applied to the latest `main` branch.

## Reporting a vulnerability
Please report vulnerabilities privately before public disclosure.

Include:
- affected version/commit
- reproduction steps
- impact assessment
- suggested mitigation (if available)

Do not open public issues for unpatched vulnerabilities.

## Repository secret policy
- Do not commit API keys, proxy credentials, tokens, certificates, or private keys.
- Do not commit local runtime data (`config.json`, `history.json` from Application Support).
- Do not commit local build artifacts and logs.

Automated checks (`pre-commit`, CI release-guard, gitleaks) enforce this policy.
