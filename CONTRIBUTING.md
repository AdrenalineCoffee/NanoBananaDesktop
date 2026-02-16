# Contributing

## Development setup
1. Clone repository
2. Install pre-commit:
   ```bash
   python3 -m pip install --user pre-commit
   pre-commit install
   ```
3. Optional (for local release guard):
   ```bash
   brew install gitleaks
   ```

## Before creating a PR
- Run tests:
  ```bash
  swift test
  ```
- Run release guard:
  ```bash
  bash scripts/release_guard.sh --ci
  ```
- Ensure no secrets or local artifacts are tracked:
  ```bash
  git ls-files | rg '^(\.build/|\.xcodebuild/|NanoBananaDesktop\.app/|\.codex/)'
  ```

## Commit policy
- Keep commits focused and atomic.
- Do not commit generated build output or local user-state files.
- Do not include API keys, passwords, or tokens in code, docs, logs, or commit messages.
