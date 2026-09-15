#!/usr/bin/env bun
/**
 * Test Bun/JavaScript Playwright integration with system Chromium
 */

import { chromium } from 'playwright';

async function test1_playwright_import() {
    console.log('Test 1: Import Playwright');
    try {
        console.log('  ✓ Playwright imported successfully');
        return true;
    } catch (error) {
        console.log(`  ✗ Failed to import Playwright: ${error}`);
        return false;
    }
}

async function test2_chromium_executable_path() {
    console.log('Test 2: Verify Chrome executable path');

    const execPath = process.env.PLAYWRIGHT_CHROME_EXECUTABLE_PATH;
    console.log(`  PLAYWRIGHT_CHROME_EXECUTABLE_PATH=${execPath}`);

    if (!execPath) {
        console.log('  ✗ Environment variable not set');
        return false;
    }

    try {
        const file = Bun.file(execPath);
        const exists = await file.exists();

        if (!exists) {
            console.log(`  ✗ Executable does not exist at ${execPath}`);
            return false;
        }

        console.log('  ✓ Chrome executable found');
        return true;
    } catch (error) {
        console.log(`  ✗ Error checking executable: ${error}`);
        return false;
    }
}

async function test3_launch_chromium() {
    console.log('Test 3: Launch Chrome browser');

    try {
        const browser = await chromium.launch({
            headless: true,
            executablePath: process.env.PLAYWRIGHT_CHROME_EXECUTABLE_PATH
        });

        const version = browser.version();
        console.log(`  ✓ Browser launched successfully`);
        console.log(`  Browser version: ${version}`);

        await browser.close();
        return true;
    } catch (error) {
        console.log(`  ✗ Failed to launch browser: ${error}`);
        console.error(error);
        return false;
    }
}

async function test4_navigate_to_page() {
    console.log('Test 4: Navigate to webpage');

    try {
        const browser = await chromium.launch({
            headless: true,
            executablePath: process.env.PLAYWRIGHT_CHROME_EXECUTABLE_PATH
        });

        const page = await browser.newPage();
        await page.goto('data:text/html,<h1>Test Page from Bun</h1>');

        const content = await page.content();
        if (!content.includes('Test Page from Bun')) {
            throw new Error('Page content verification failed');
        }

        console.log('  ✓ Successfully navigated and read page content');

        await browser.close();
        return true;
    } catch (error) {
        console.log(`  ✗ Failed to navigate: ${error}`);
        console.error(error);
        return false;
    }
}

async function main() {
    console.log('=== Testing Bun/JavaScript Playwright ===\n');

    const tests = [
        test1_playwright_import,
        test2_chromium_executable_path,
        test3_launch_chromium,
        test4_navigate_to_page,
    ];

    const results = [];

    for (const test of tests) {
        try {
            const result = await test();
            results.push(result);
        } catch (error) {
            console.log(`  ✗ Test crashed: ${error}`);
            results.push(false);
        }
        console.log();
    }

    const passed = results.filter(r => r).length;
    const total = results.length;

    console.log(`=== Results: ${passed}/${total} tests passed ===`);

    if (passed === total) {
        console.log('=== Bun/JavaScript Playwright tests PASSED ===');
        process.exit(0);
    } else {
        console.log('=== Bun/JavaScript Playwright tests FAILED ===');
        process.exit(1);
    }
}

main();
