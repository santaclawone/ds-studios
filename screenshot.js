const puppeteer = require('puppeteer');
const path = require('path');

const url = process.argv[2];
const outputPath = process.argv[3] || 'screenshot.png';

if (!url) {
  console.error('Usage: node screenshot.js <url> [output.png]');
  process.exit(1);
}

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36');

  try {
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    // Extra wait for any lazy-loaded content
    await new Promise(r => setTimeout(r, 2000));
    await page.screenshot({ path: outputPath, fullPage: false });
    console.log(`Screenshot saved: ${outputPath}`);
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();
