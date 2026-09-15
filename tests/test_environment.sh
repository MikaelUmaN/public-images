#!/bin/bash
set -e

echo "=== Testing Basic Environment ==="

# Test 1: Verify user
echo "Test 1: Current user"
whoami | grep -q ubuntu || exit 1

# Test 2: Python installation
echo "Test 2: Python version"
python3 --version
uv --version

# Test 3: Bun installation
echo "Test 3: Bun runtime"
bun --version
node --version  # Should be symlinked to bun

# Test 4: Essential CLI tools
echo "Test 4: CLI tools"
aws --version
kubectl version --client
duckdb --version
ruff --version
claude --version

# Test 5: ~/.local/bin on PATH without a login shell
echo "Test 5: user bin directory on PATH"
case ":${PATH}:" in *":${HOME}/.local/bin:"*) ;; *) exit 1 ;; esac
command -v claude | grep -qF "${HOME}/.local/bin/claude" || exit 1

# Test 6: Environment variables
echo "Test 6: Playwright environment variables"
echo "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD}"
echo "PLAYWRIGHT_CHROME_EXECUTABLE_PATH=${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}"

echo "=== Basic environment tests PASSED ==="
