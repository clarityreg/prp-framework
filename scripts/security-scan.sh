#!/usr/bin/env bash
# ============================================================
# Command Center - Security Scan
# Runs Trivy to check for vulnerabilities and leaked secrets
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=== Command Center Security Scan ==="
echo ""

# Check Trivy is installed
if ! command -v trivy &> /dev/null; then
    echo "ERROR: Trivy is not installed."
    echo "Install: brew install trivy"
    echo "   or:   curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh"
    exit 1
fi

FAILED=0

# 1. Secret Detection (most critical)
echo "--- Secret Detection ---"
if trivy fs --scanners secret --severity HIGH,CRITICAL --exit-code 1 \
    --skip-dirs node_modules,.svelte-kit,build,dist,target,.venv,venv,__pycache__,.git \
    --skip-files "*.db" \
    . 2>&1; then
    echo "PASS: No secrets detected"
else
    echo "FAIL: Secrets found! Check output above."
    FAILED=1
fi
echo ""

# 2. Dependency Vulnerabilities
echo "--- Dependency Vulnerabilities ---"
if trivy fs --scanners vuln --severity HIGH,CRITICAL \
    --skip-dirs node_modules,.svelte-kit,build,dist,target,.venv,venv,__pycache__,.git \
    . 2>&1; then
    echo "Vulnerability scan complete"
else
    echo "WARNING: Vulnerability scan found issues (check above)"
    FAILED=1
fi
echo ""

# 3. Summary
if [ $FAILED -eq 0 ]; then
    echo "=== Security scan PASSED ==="
else
    echo "=== Security scan FAILED ==="
    echo "Fix the issues above before committing."
    exit 1
fi
