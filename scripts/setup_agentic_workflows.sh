#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: Authenticate first with: gh auth login --scopes repo,workflow"
  exit 1
fi

if ! gh extension list | awk '{print $1}' | grep -qx 'github/gh-aw'; then
  echo "Installing GitHub Agentic Workflows extension..."
  gh extension install github/gh-aw
fi

echo "Initializing repository for OpenAI Codex agentic workflows..."
gh aw init --engine codex

echo "Compiling agent workflow Markdown sources..."
gh aw compile

echo
echo "Compilation complete."
echo "Next steps:"
echo "  1. Add the OpenAI secret: gh secret set OPENAI_API_KEY"
echo "  2. Review generated .github/workflows/*.lock.yml files"
echo "  3. Commit and push the generated lock files"
echo "  4. Merge the control-plane setup to main"
echo "  5. Apply label agent-dev to issue #3 to start the agent chain"
