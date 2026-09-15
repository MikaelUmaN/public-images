#!/bin/bash
set -e

echo "=== Testing System Chrome ==="

# Test 1: Check if google-chrome-stable package is installed
echo "Test 1: Package installation"
dpkg -l | grep google-chrome-stable

# Test 2: Find actual chrome executables
echo "Test 2: Locate chrome executables"
which google-chrome-stable || echo "google-chrome-stable not in PATH"
ls -l /usr/bin/google-chrome* || echo "No google-chrome in /usr/bin"

# Test 3: Verify Chrome repository
echo "Test 3: Chrome repository"
if [ -f /etc/apt/sources.list.d/google-chrome.list ]; then
    echo "  ✓ Chrome repository configured"
else
    echo "  ✗ Chrome repository NOT configured"
fi

# Test 4: Check actual executable at ENV path
echo "Test 4: Check PLAYWRIGHT_CHROME_EXECUTABLE_PATH"
if [ -f "${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}" ]; then
    echo "Found: ${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}"
    file "${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}"
    ls -l "${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}"
else
    echo "ERROR: ${PLAYWRIGHT_CHROME_EXECUTABLE_PATH} does not exist"
    exit 1
fi

# Test 5: Try to execute chrome with --version
echo "Test 5: Execute chrome"
"${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}" --version || {
    echo "ERROR: Cannot execute chrome"
    exit 1
}

# Test 6: Check for required shared libraries
echo "Test 6: Check shared library dependencies"
ldd "${PLAYWRIGHT_CHROME_EXECUTABLE_PATH}" | head -20

# Test 7: Verify system libraries are installed
echo "Test 7: Verify required libraries"
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
    "fonts-liberation"
    "libatk1.0-0"
    "libcups2"
    "libdbus-1-3"
)

for lib in "${required_libs[@]}"; do
    if dpkg -l | grep -q "^ii.*${lib}"; then
        echo "  ✓ ${lib} installed"
    else
        echo "  ✗ ${lib} MISSING"
        exit 1
    fi
done

echo "=== System Chrome tests PASSED ==="
