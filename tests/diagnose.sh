#!/bin/bash

echo "=== Diagnostic Information ==="
echo ""

echo "1. Environment Variables:"
env | grep -E "(PLAYWRIGHT|PATH|HOME|USER)" | sort

echo ""
echo "2. Chrome Package Info:"
dpkg -l | grep google-chrome || echo "No google-chrome packages found"

echo ""
echo "3. Chrome Executables:"
find /usr 2>/dev/null -name "google-chrome*" -type f -executable 2>/dev/null || echo "No google-chrome executables found"

echo ""
echo "4. PLAYWRIGHT_CHROME_EXECUTABLE_PATH status:"
if [ -n "$PLAYWRIGHT_CHROME_EXECUTABLE_PATH" ]; then
    echo "  Path: $PLAYWRIGHT_CHROME_EXECUTABLE_PATH"
    if [ -f "$PLAYWRIGHT_CHROME_EXECUTABLE_PATH" ]; then
        echo "  Exists: Yes"
        echo "  Type: $(file "$PLAYWRIGHT_CHROME_EXECUTABLE_PATH")"
        echo "  Executable: $(test -x "$PLAYWRIGHT_CHROME_EXECUTABLE_PATH" && echo Yes || echo No)"
    else
        echo "  Exists: No"
    fi
else
    echo "  Not set"
fi

echo ""
echo "5. Required System Libraries:"
required_libs=(
    "libatk-bridge2.0-0"
    "libdrm2"
    "libxcomposite1"
    "libxdamage1"
    "libxrandr2"
    "libgbm1"
    "libxkbcommon0"
    "libasound2"
    "libpango-1.0-0"
    "libcairo2"
)

for lib in "${required_libs[@]}"; do
    if dpkg -l | grep -q "^ii.*${lib}"; then
        echo "  ✓ ${lib}"
    else
        echo "  ✗ ${lib} MISSING"
    fi
done

echo ""
echo "6. Playwright Installations:"
echo "  Python:"
cd /home/ubuntu/jupyter 2>/dev/null && uv run python -c "import playwright; print('    Version:', playwright.__version__); print('    Path:', playwright.__file__)" 2>&1 || echo "    Not installed or error"

echo "  Bun:"
bun -e "import pkg from 'playwright/package.json'; console.log('    Version:', pkg.version)" 2>&1 || echo "    Not installed or error"

echo ""
echo "7. Chrome Repository:"
if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
    echo "  ✓ Chrome repository configured"
    cat /etc/apt/sources.list.d/google-chrome.list
else
    echo "  ✗ Chrome repository NOT configured"
fi

echo ""
echo "=== End Diagnostic ==="
