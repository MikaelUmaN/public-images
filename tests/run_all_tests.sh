#!/bin/bash
set -e

echo "=========================================="
echo "  Datascience Docker Image Test Suite"
echo "=========================================="
echo ""

FAILED_TESTS=()

run_test() {
    local test_name="$1"
    local test_command="$2"

    echo "----------------------------------------"
    echo "Running: $test_name"
    echo "----------------------------------------"

    if eval "$test_command"; then
        echo "✓ $test_name PASSED"
        echo ""
        return 0
    else
        echo "✗ $test_name FAILED"
        FAILED_TESTS+=("$test_name")
        echo ""
        return 1
    fi
}

# Run all tests
run_test "Environment Test" "bash /tests/test_environment.sh" || true
run_test "Chrome System Test" "bash /tests/test_chrome_system.sh" || true
run_test "Perf System Test" "bash /tests/test_perf.sh" || true
run_test "Python Playwright Test" "cd /home/ubuntu/jupyter && uv sync && uv run python /tests/test_playwright_python.py" || true
run_test "Bun Playwright Test" "bun /tests/test_playwright_bun.js" || true
run_test "E2E Browser Test" "cd /home/ubuntu/jupyter && uv run python /tests/test_e2e_browser.py" || true

# Summary
echo "=========================================="
echo "  Test Summary"
echo "=========================================="

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "✓ All tests PASSED"
    exit 0
else
    echo "✗ ${#FAILED_TESTS[@]} test(s) FAILED:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    exit 1
fi
