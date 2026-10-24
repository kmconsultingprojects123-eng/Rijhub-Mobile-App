// Renders concepts/app-icons.html: each icon drawn at 2x (2048 px, for a
// clean Lanczos step down to 1024 afterwards), and the review sheet.
//
//   node scripts/render-icons.mjs OUT_DIR
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const page = path.join(here, '..', 'concepts', 'app-icons.html');
const out = path.resolve(process.argv[2] || path.join(here, '..', 'out', 'icons'));
fs.mkdirSync(out, { recursive: true });

// The page reads the logo's paths from its file, which Chrome only allows
// file pages to do with this flag.
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--allow-file-access-from-files'] });
const icons = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 2 });
for (let v = 1; v <= 5; v++) {
  await icons.goto(`file://${page}?v=${v}`);
  await icons.waitForSelector('body[data-ready="1"]');
  await icons.waitForLoadState('networkidle');
  await icons.evaluate(() => document.fonts.ready);
  await icons.screenshot({ path: path.join(out, `.icon-${v}@2x.png`), clip: { x: 0, y: 0, width: 1024, height: 1024 } });
}
const sheet = await browser.newPage({ viewport: { width: 3600, height: 1000 }, deviceScaleFactor: 1 });
await sheet.goto(`file://${page}?sheet=1`);
await sheet.waitForSelector('body[data-ready="1"]');
await sheet.waitForLoadState('networkidle');
await sheet.evaluate(() => document.fonts.ready);
await sheet.locator('#sheet').screenshot({ path: path.join(out, 'app-icon-variants.png') });
await browser.close();
console.log(`rendered 5 icons and the sheet into ${out}`);
