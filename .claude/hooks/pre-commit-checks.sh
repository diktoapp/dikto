#!/usr/bin/env bash
#
# Claude Code PreToolUse hook for Bash commands.
# Intercepts `git commit` and runs the same checks as CI before allowing it.
# Exit 0 = allow, exit 2 = block the tool use.

set -euo pipefail

INPUT=$(cat)

# Extract the command from the JSON input
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

# Only gate git commit commands — let everything else through
if ! echo "$COMMAND" | grep -qE '(^|\s|&&|\||\;)git\s+commit(\s|$)'; then
  exit 0
fi

echo "Pre-commit hook: running CI checks before committing..."
echo ""

cd "$CLAUDE_PROJECT_DIR"

echo "==> cargo fmt --check --all"
if ! cargo fmt --check --all; then
  echo ""
  echo "BLOCKED: cargo fmt found formatting issues. Run 'cargo fmt --all' to fix."
  exit 2
fi

echo ""
echo "==> cargo clippy --all-targets -- -D warnings"
if ! cargo clippy --all-targets -- -D warnings; then
  echo ""
  echo "BLOCKED: cargo clippy found warnings. Fix them before committing."
  exit 2
fi

echo ""
echo "==> cargo test --workspace"
if ! cargo test --workspace; then
  echo ""
  echo "BLOCKED: cargo test failed. Fix tests before committing."
  exit 2
fi

echo ""
echo "All CI checks passed."
exit 0
