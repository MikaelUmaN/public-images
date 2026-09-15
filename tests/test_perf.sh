#!/bin/bash
# Test perf functionality (requires perf mounted from host)
set -e

echo "=== Perf System Test ==="

# Check if perf is available
echo "1. Checking perf binary..."
if [ -x "/usr/local/bin/perf" ]; then
    echo "   perf found at /usr/local/bin/perf"
    PERF_PATH="/usr/local/bin/perf"
elif [ -x "/usr/bin/perf" ]; then
    echo "   perf found at /usr/bin/perf"
    PERF_PATH="/usr/bin/perf"
else
    echo "   perf not found (host mount may be missing)"
    echo "   Expected mount: -v /usr/local/bin/perf:/usr/local/bin/perf:ro"
    exit 0  # Not a failure - perf mount is optional
fi

# Check shared library dependencies
echo "2. Checking shared library dependencies..."
if ldd "$PERF_PATH" 2>/dev/null | grep -q "not found"; then
    echo "   Missing libraries:"
    ldd "$PERF_PATH" 2>/dev/null | grep "not found" || true
    exit 1
else
    echo "   All shared libraries available"
fi

# Check specific libraries we install (Ubuntu 24.04 uses t64 suffix for some packages)
echo "3. Checking installed perf runtime libraries..."
REQUIRED_LIBS=("libdw1t64" "libunwind8" "libslang2" "libdebuginfod1t64" "libpfm4")
for lib in "${REQUIRED_LIBS[@]}"; do
    if dpkg -l "$lib" 2>/dev/null | grep -q "^ii"; then
        echo "   $lib installed"
    else
        echo "   $lib NOT installed"
    fi
done

# Try running perf version
echo "4. Running perf version..."
if "$PERF_PATH" version 2>&1; then
    echo "   perf runs successfully"
else
    echo "   perf failed to run"
    exit 1
fi

echo ""
echo "=== Perf Test PASSED ==="
