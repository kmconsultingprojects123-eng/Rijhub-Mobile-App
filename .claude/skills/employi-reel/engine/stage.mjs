// Opens the stage in headless Chrome with the reel's three inputs injected.
//
// Inputs default to the skill's own brand.json, reel.json and cues.json;
// BRAND=, REEL= and CUES= (paths) override them, which is how a variant is
// rendered without touching the original.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ENGINE = path.dirname(fileURLToPath(import.meta.url));
export const SKILL = path.dirname(ENGINE);
const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const pick = (env, file) => (process.env[env] ? path.resolve(process.env[env]) : path.join(SKILL, file));

export function config() {
  return { brand: read(pick('BRAND', 'brand.json')), reel: read(pick('REEL', 'reel.json')), cues: read(pick('CUES', 'cues.json')) };
}

export async function openStage() {
  const cfg = config();
  const browser = await chromium.launch({
    channel: 'chrome', headless: true,
    args: ['--force-color-profile=srgb', '--disable-lcd-text', '--allow-file-access-from-files', '--hide-scrollbars'],
  });
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));
  // missing files are reported once, as a list, by missing(); not line by line here
  page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_FILE_NOT_FOUND')) console.log('console:', m.text()); });
  await page.addInitScript((c) => { window.BRAND = c.brand; window.REEL = c.reel; window.CUES = c.cues; }, cfg);
  await page.goto('file://' + path.join(ENGINE, 'index.html'));
  await page.evaluate(() => window.ready());
  return { browser, page, cfg };
}

// Media the page could not load. Any entry means a placeholder was drawn.
export const missing = (page) => page.evaluate(() => [...window.MISSING]);
