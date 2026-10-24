// node render.mjs OUT_DIR page.html[?query] [...]
//
// Draws each concept page in headless Chrome at twice the store size, then
// scripts/finish.py brings it down to the exact size as an RGB PNG (no alpha:
// App Store Connect and Play Console both refuse transparency). Before the
// capture, every information element the page registered is checked: no two
// overlap unless the page allows it, and no text sits outside the margins.
// Exits non-zero on any problem; the PNG is still written, to look at.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const [out, ...pages] = process.argv.slice(2);
if (!out || !pages.length) { console.log('usage: node render.mjs OUT_DIR page.html [...]'); process.exit(64); }
fs.mkdirSync(out, { recursive: true });
const SUPER = Number(process.env.SUPER || 2);

function corners({ cx, cy, w, h, r }) {
  const a = (r * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
  return [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]].map(([x, y]) => [cx + x * c - y * s, cy + x * s + y * c]);
}
function overlap(A, B) { // depth along the best separating axis; <= 0 means apart
  let min = Infinity;
  for (const poly of [A, B]) for (let i = 0; i < 4; i++) {
    const [x1, y1] = poly[i], [x2, y2] = poly[(i + 1) % 4];
    const nx = y2 - y1, ny = x1 - x2, L = Math.hypot(nx, ny);
    const pa = A.map(([x, y]) => (x * nx + y * ny) / L), pb = B.map(([x, y]) => (x * nx + y * ny) / L);
    min = Math.min(min, Math.min(Math.max(...pa), Math.max(...pb)) - Math.max(Math.min(...pa), Math.min(...pb)));
  }
  return min;
}

const browser = await chromium.launch({ channel: 'chrome', headless: true,
  args: ['--force-color-profile=srgb', '--disable-lcd-text', '--allow-file-access-from-files', '--hide-scrollbars'] });
let problems = 0;
for (const p of pages) {
  // page.html?slide=2&format=ipad: the query picks what the page draws, and
  // the page names its own output (window.NAME).
  const [rel, query = ''] = p.split('?');
  const url = 'file://' + path.resolve(rel) + (query ? `?${query}` : '');
  const probe = await browser.newPage({ viewport: { width: 400, height: 400 } });
  await probe.goto(url);
  const [W, H] = await probe.evaluate(() => window.SIZE || [1320, 2868]);
  const name = await probe.evaluate(() => window.NAME) || path.basename(rel, '.html');
  await probe.close();

  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: SUPER });
  page.on('pageerror', (e) => { console.log(`${name}: PAGE ERROR ${e.message}`); problems++; });
  page.on('console', (m) => { if (m.type() === 'error') { console.log(`${name}: CONSOLE ${m.text()}`); problems++; } });
  page.on('requestfailed', (r) => { console.log(`${name}: MISSING ${r.url()}`); problems++; });
  await page.goto(url);
  const { boxes, allow, margin } = await page.evaluate(() => window.ready());
  const ok = (a, b) => allow.includes(`${a}|${b}`) || allow.includes(`${b}|${a}`);
  const polys = Object.fromEntries(Object.entries(boxes).map(([k, b]) => [k, { p: corners(b), text: b.text, bleed: b.bleed }]));
  const keys = Object.keys(polys);
  for (let i = 0; i < keys.length; i++) for (let j = i + 1; j < keys.length; j++) {
    const d = overlap(polys[keys[i]].p, polys[keys[j]].p);
    if (d > 0 && !ok(keys[i], keys[j])) { console.log(`${name}: OVERLAP ${keys[i]} x ${keys[j]} (${d.toFixed(1)}px)`); problems++; }
  }
  for (const [k, { p, text, bleed }] of Object.entries(polys)) {
    if (bleed) continue;
    const xs = p.map((c) => c[0]), ys = p.map((c) => c[1]);
    const m = text ? margin : 0;
    if (Math.min(...xs) < m || Math.max(...xs) > W - m || Math.min(...ys) < m || Math.max(...ys) > H - m) {
      console.log(`${name}: MARGIN ${k} x ${Math.min(...xs).toFixed(0)}..${Math.max(...xs).toFixed(0)} y ${Math.min(...ys).toFixed(0)}..${Math.max(...ys).toFixed(0)}`); problems++;
    }
  }
  const big = path.join(out, `.${name}@${SUPER}x.png`);
  await page.locator('#canvas').screenshot({ path: big });
  await page.close();
  const final = path.join(out, `${name}.png`);
  execFileSync('/usr/bin/python3', [path.join(HERE, 'scripts/finish.py'), big, final, String(W), String(H)], { stdio: 'inherit' });
  fs.unlinkSync(big);
  fs.writeFileSync(path.join(out, `${name}.boxes.json`), JSON.stringify(boxes, null, 1));
}
await browser.close();
console.log(problems ? `${problems} problem(s)` : 'no overlaps, margins ok');
process.exit(problems ? 1 : 0);
