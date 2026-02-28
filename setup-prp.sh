#!/bin/bash
# setup-prp.sh - Initialize PRP Framework for Claude Code
# Run this once after cloning the repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"

echo "Setting up PRP Framework..."

# Ensure hooks directory exists
mkdir -p "$HOOKS_DIR/sounds/voice"

# Copy settings template if no settings exist
if [ ! -f "$CLAUDE_DIR/prp-settings.json" ]; then
    if [ -f "$CLAUDE_DIR/prp-settings.template.json" ]; then
        cp "$CLAUDE_DIR/prp-settings.template.json" "$CLAUDE_DIR/prp-settings.json"
        echo "Created prp-settings.json from template"
    fi
fi

# Make hook scripts executable
chmod +x "$HOOKS_DIR/hook_handler.py" 2>/dev/null || true
chmod +x "$HOOKS_DIR/verify_file_size.py" 2>/dev/null || true
chmod +x "$HOOKS_DIR/structure_change.py" 2>/dev/null || true
chmod +x "$HOOKS_DIR/auto-format.sh" 2>/dev/null || true

# Make pre-commit scripts executable
chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts/"*.py 2>/dev/null || true

# Check for required dependencies
echo "Checking dependencies..."

if ! command -v python3 &> /dev/null; then
    echo "Warning: python3 not found. Hooks require Python 3."
fi

if ! command -v say &> /dev/null; then
    echo "Warning: 'say' command not found. Audio hooks require macOS."
fi

# Install pre-commit hooks
if command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit hooks..."
    pre-commit install
    echo "Pre-commit hooks installed."
else
    echo "Warning: pre-commit not found. Install with: pip install pre-commit"
    echo "  Then run: pre-commit install"
fi

# Check optional tools
for tool in trivy coderabbit ruff; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Warning: $tool not found (optional pre-commit hook)."
    fi
done

# Generate audio files (macOS only)
if command -v say &> /dev/null && command -v afplay &> /dev/null; then
    echo "Generating audio files..."
    python3 "$HOOKS_DIR/hook_handler.py" --generate-all
    echo "Audio files generated in $HOOKS_DIR/sounds/voice/"
else
    echo "Skipping audio generation (not macOS or missing commands)"
fi

# Install observability dashboard dependencies
if command -v bun &> /dev/null; then
    echo "Installing observability dashboard dependencies..."
    if [ -d "$SCRIPT_DIR/apps/server" ]; then
        (cd "$SCRIPT_DIR/apps/server" && bun install --silent)
        echo "  Server dependencies installed."
    fi
    if [ -d "$SCRIPT_DIR/apps/client" ]; then
        (cd "$SCRIPT_DIR/apps/client" && bun install --silent)
        echo "  Client dependencies installed."
    fi
    chmod +x "$SCRIPT_DIR/scripts/start-observability.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/scripts/stop-observability.sh" 2>/dev/null || true
else
    echo "Warning: bun not found. Observability dashboard requires Bun."
    echo "  Install with: curl -fsSL https://bun.sh/install | bash"
fi

# Verify settings.json exists
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo "Settings file: $CLAUDE_DIR/settings.json"
else
    echo "Warning: settings.json not found. Copy from settings.template.json"
fi

echo ""
echo "PRP Framework setup complete!"
echo ""
echo "Directory structure:"
echo "  .claude/"
echo "  ├── settings.json         # Hook configuration"
echo "  ├── prp-settings.json     # Project settings"
echo "  ├── hooks/                # Hook scripts + observability/"
echo "  ├── commands/             # PRP slash commands"
echo "  ├── templates/ci/         # CI workflow templates"
echo "  ├── agents/               # Agent definitions"
echo "  └── PRPs/                 # Artifact storage"
echo "  apps/"
echo "  ├── server/               # Observability server (Bun)"
echo "  └── client/               # Observability dashboard (Vue)"
echo ""
echo "Available commands:"
echo "  /prp-prd          - Generate Product Requirements"
echo "  /prp-plan         - Create implementation plan"
echo "  /prp-implement    - Execute plan"
echo "  /prp-validate     - Run validation checks"
echo "  /prp-coderabbit   - AI code review"
echo "  /prp-ci-init      - Initialize CI/CD workflows"
echo "  /prp-coverage     - Generate coverage reports"
echo "  /prp-branches     - Branch/PR visualization"
echo "  /prp-commit       - Smart git commit"
echo "  /prp-pr           - Create pull request"
echo ""
echo "To test hooks: python3 .claude/hooks/hook_handler.py --play ready"
