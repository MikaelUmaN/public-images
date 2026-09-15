#!/usr/bin/env python3
"""Test Python Playwright integration with system Chromium"""

import sys
import os
from pathlib import Path

def test_1_playwright_import():
    """Test 1: Import Playwright"""
    print("Test 1: Import Playwright")
    try:
        from playwright.sync_api import sync_playwright
        print("  ✓ Playwright imported successfully")
        return True
    except ImportError as e:
        print(f"  ✗ Failed to import Playwright: {e}")
        return False

def test_2_playwright_installation():
    """Test 2: Check Playwright installation"""
    print("Test 2: Check Playwright installation")
    from playwright.sync_api import sync_playwright

    try:
        with sync_playwright() as p:
            print(f"  ✓ Playwright initialized successfully")
            return True
    except Exception as e:
        print(f"  ✗ Error initializing Playwright: {e}")
        return False

def test_3_chromium_executable_path():
    """Test 3: Verify Chrome executable path"""
    print("Test 3: Verify Chrome executable path")

    exec_path = os.environ.get('PLAYWRIGHT_CHROME_EXECUTABLE_PATH')
    print(f"  PLAYWRIGHT_CHROME_EXECUTABLE_PATH={exec_path}")

    if not exec_path:
        print("  ✗ Environment variable not set")
        return False

    if not Path(exec_path).exists():
        print(f"  ✗ Executable does not exist at {exec_path}")
        return False

    if not Path(exec_path).is_file():
        print(f"  ✗ Path exists but is not a file")
        return False

    if not os.access(exec_path, os.X_OK):
        print(f"  ✗ File exists but is not executable")
        return False

    print(f"  ✓ Chrome executable found and executable")
    return True

def test_4_launch_chromium():
    """Test 4: Launch Chrome browser"""
    print("Test 4: Launch Chrome browser")
    from playwright.sync_api import sync_playwright

    try:
        with sync_playwright() as p:
            # Launch with system Chrome
            browser = p.chromium.launch(
                headless=True,
                executable_path=os.environ.get('PLAYWRIGHT_CHROME_EXECUTABLE_PATH')
            )
            print(f"  ✓ Browser launched successfully")
            print(f"  Browser version: {browser.version}")
            browser.close()
            return True
    except Exception as e:
        print(f"  ✗ Failed to launch browser: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_5_navigate_to_page():
    """Test 5: Navigate to a webpage"""
    print("Test 5: Navigate to webpage")
    from playwright.sync_api import sync_playwright

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=True,
                executable_path=os.environ.get('PLAYWRIGHT_CHROME_EXECUTABLE_PATH')
            )
            page = browser.new_page()

            # Navigate to a simple page
            page.goto('data:text/html,<h1>Test Page</h1>')

            # Verify content
            content = page.content()
            assert 'Test Page' in content

            print(f"  ✓ Successfully navigated and read page content")
            browser.close()
            return True
    except Exception as e:
        print(f"  ✗ Failed to navigate: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    print("=== Testing Python Playwright ===\n")

    tests = [
        test_1_playwright_import,
        test_2_playwright_installation,
        test_3_chromium_executable_path,
        test_4_launch_chromium,
        test_5_navigate_to_page,
    ]

    results = []
    for test in tests:
        try:
            result = test()
            results.append(result)
        except Exception as e:
            print(f"  ✗ Test crashed: {e}")
            results.append(False)
        print()

    passed = sum(results)
    total = len(results)

    print(f"=== Results: {passed}/{total} tests passed ===")

    if passed == total:
        print("=== Python Playwright tests PASSED ===")
        return 0
    else:
        print("=== Python Playwright tests FAILED ===")
        return 1

if __name__ == '__main__':
    sys.exit(main())
