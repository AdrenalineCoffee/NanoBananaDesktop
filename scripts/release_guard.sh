#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:---ci}"

FORBIDDEN_REGEX='^(\.build/|\.xcodebuild/|NanoBananaDesktop\.app/|\.codex/|.*\/xcuserdata/|.*\.xcuserstate$|.*\.DS_Store$|.*\.log$|AppIcon\.icns$|Icon\.png$|Icon-converted\.png$|New_icon\.png$)'

echo "[release-guard] mode: $MODE"
echo "[release-guard] repository: $ROOT_DIR"

check_forbidden_tracked_paths() {
  echo "[release-guard] checking forbidden tracked paths..."
  local matches
  matches="$(git ls-files | rg "$FORBIDDEN_REGEX" || true)"
  if [[ -n "$matches" ]]; then
    echo "[release-guard] ERROR: forbidden tracked files detected:"
    echo "$matches"
    exit 1
  fi
  echo "[release-guard] forbidden tracked paths: OK"
}

check_obvious_secret_patterns() {
  echo "[release-guard] checking obvious secret patterns..."
  # High-signal patterns only; gitleaks does deep scanning.
  local matches
  matches="$(
    git ls-files \
      | rg -v '^(\.build/|\.xcodebuild/|NanoBananaDesktop\.app/)' \
      | xargs rg -n --no-heading \
        -e 'AIza[0-9A-Za-z_-]{20,}' \
        -e 'sk-[A-Za-z0-9]{20,}' \
        -e 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY' \
        -e 'api[_-]?key[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']' \
        -e 'proxyPassword[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']' \
      || true
  )"
  if [[ -n "$matches" ]]; then
    echo "[release-guard] ERROR: potential secret patterns detected:"
    echo "$matches"
    exit 1
  fi
  echo "[release-guard] obvious secret patterns: OK"
}

check_large_tracked_files() {
  echo "[release-guard] checking large tracked files (>10MB)..."
  local found=0
  while IFS= read -r line; do
    local size path
    size="$(awk '{print $1}' <<<"$line")"
    path="$(awk '{$1=""; sub(/^ /,""); print}' <<<"$line")"
    if [[ "$size" -gt 10485760 ]]; then
      echo "[release-guard] large tracked file: $path ($size bytes)"
      found=1
    fi
  done < <(git ls-files -z | xargs -0 stat -f '%z %N')

  if [[ "$found" -eq 1 ]]; then
    echo "[release-guard] ERROR: large tracked files detected."
    exit 1
  fi
  echo "[release-guard] large tracked files: OK"
}

run_gitleaks_if_available() {
  if command -v gitleaks >/dev/null 2>&1; then
    echo "[release-guard] running gitleaks..."
    gitleaks detect --source . --no-banner --redact --verbose
    echo "[release-guard] gitleaks: OK"
  else
    echo "[release-guard] gitleaks not found in PATH; skipping (handled separately in CI/pre-commit)."
  fi
}

check_forbidden_tracked_paths
check_obvious_secret_patterns
check_large_tracked_files

case "$MODE" in
  --pre-commit)
    # gitleaks runs as a dedicated pre-commit hook.
    ;;
  --ci)
    run_gitleaks_if_available
    ;;
  *)
    echo "[release-guard] unknown mode: $MODE"
    echo "[release-guard] use --pre-commit or --ci"
    exit 1
    ;;
esac

echo "[release-guard] all checks passed."
