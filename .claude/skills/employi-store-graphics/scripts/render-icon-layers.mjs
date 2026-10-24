// Renders one icon's Android adaptive layers (background, foreground and
// monochrome) at 2x, for a Lanczos step down to 1024 afterwards.
//
//   node scripts/render-icon-layers.mjs VARIANT OUT_DIR
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const page = path.join(here, '..', 'concepts', 'app-icons.html');
const [v = '5', outArg] = process.argv.slice(2);
const out = path.resolve(outArg || path.join(here, '..', 'out', 'icon-layers'));
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--allow-file-access-from-files'] });
const tab = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 2 });
for (const layer of ['bg', 'fg', 'mono']) {
  await tab.goto(`file://${page}?v=${v}&layer=${layer}&zoom=0.6667`);
  await tab.waitForSelector('body[data-ready="1"]');
  await tab.waitForLoadState('networkidle');
  await tab.screenshot({ path: path.join(out, `.${layer}@2x.png`), clip: { x: 0, y: 0, width: 1024, height: 1024 }, omitBackground: layer !== 'bg' });
}
await browser.close();
console.log(`rendered variant ${v}'s adaptive layers into ${out}`);
