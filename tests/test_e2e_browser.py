#!/usr/bin/env python3
"""End-to-end browser automation test"""

import sys
import os
from playwright.sync_api import sync_playwright

def test_realistic_scenario():
    """Test realistic web scraping/automation scenario"""
    print("=== End-to-End Browser Automation Test ===\n")

    try:
        with sync_playwright() as p:
            print("Step 1: Launch browser")
            browser = p.chromium.launch(
                headless=True,
                executable_path=os.environ.get('PLAYWRIGHT_CHROME_EXECUTABLE_PATH'),
                args=['--no-sandbox', '--disable-setuid-sandbox']  # Container-friendly args
            )
            print("  ✓ Browser launched")

            print("\nStep 2: Create context and page")
            context = browser.new_context(
                viewport={'width': 1280, 'height': 720},
                user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
            )
            page = context.new_page()
            print("  ✓ Context and page created")

            print("\nStep 3: Navigate to example.com")
            page.goto('http://example.com', wait_until='networkidle')
            print(f"  ✓ Navigated to {page.url}")

            print("\nStep 4: Extract page title")
            title = page.title()
            print(f"  ✓ Page title: {title}")

            print("\nStep 5: Take screenshot")
            screenshot = page.screenshot()
            print(f"  ✓ Screenshot captured ({len(screenshot)} bytes)")

            print("\nStep 6: Query selector")
            heading = page.query_selector('h1')
            if heading:
                text = heading.inner_text()
                print(f"  ✓ Found heading: {text}")

            print("\nStep 7: Execute JavaScript")
            result = page.evaluate('() => document.querySelector("h1").textContent')
            print(f"  ✓ JavaScript execution result: {result}")

            print("\nStep 8: Clean up")
            context.close()
            browser.close()
            print("  ✓ Browser closed")

            print("\n=== E2E Test PASSED ===")
            return 0

    except Exception as e:
        print(f"\n✗ Test FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(test_realistic_scenario())
