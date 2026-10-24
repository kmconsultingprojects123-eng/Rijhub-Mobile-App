// node shoot.mjs OUT_DIR SCALE page[:Q] ...  -> OUT_DIR/page.png (SCALE 3 = the 3240x4050 HD master)
// A page with :Q gets assets/qrQ.svg for its QR; one without gets none (and
// common.js refuses to draw a QR while APP_URL is a TODO). Captures are read
// from SCREENS (default ~/Downloads/employi-screens).
// Checks every page for overlapping information elements, safe margins and
// missing files before capturing; exits non-zero if anything fails.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
// playwright-core comes from employi-reel's engine (npm install there once).
import { chromium } from '/Users/adedayo/Desktop/projects/flutter/Rijhub-Mobile-App/.claude/skills/employi-reel/engine/node_modules/playwright-core/index.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCREENS = process.env.SCREENS || path.join(os.homedir(), 'Downloads', 'employi-screens');
const [out, scaleArg, ...concepts] = process.argv.slice(2);
const scale = Number(scaleArg || 1);
fs.mkdirSync(out, { recursive: true });
const W = 1080, H = 1350, MX = 48, MT = 40, MB = 30;

function corners({ cx, cy, w, h, r }) {
  const a = (r * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
  return [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]].map(([x, y]) => [cx + x * c - y * s, cy + x * s + y * c]);
}
function satOverlap(A, B) { // depth of overlap along the best separating axis (<= 0: apart)
  let min = Infinity;
  for (const poly of [A, B]) for (let i = 0; i < 4; i++) {
    const [x1, y1] = poly[i], [x2, y2] = poly[(i + 1) % 4];
    const nx = y2 - y1, ny = x1 - x2, L = Math.hypot(nx, ny);
    const pa = A.map(([x, y]) => (x * nx + y * ny) / L), pb = B.map(([x, y]) => (x * nx + y * ny) / L);
    const o = Math.min(Math.max(...pa), Math.max(...pb)) - Math.max(Math.min(...pa), Math.min(...pb));
    min = Math.min(min, o);
  }
  return min;
}

const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--force-color-profile=srgb', '--disable-lcd-text', '--allow-file-access-from-files', '--hide-scrollbars'] });
let problems = 0;
for (const spec of concepts) {
  const [name, qn] = spec.split(':');
  const qrsvg = qn ? fs.readFileSync(path.join(HERE, `assets/qr${qn}.svg`), 'utf8') : null;
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: scale });
  let thrown = 0;     // a page that throws (a refusal, say) is never captured
  page.on('pageerror', (e) => { console.log(`${name}: PAGE ERROR ${e.message}`); problems++; thrown++; });
  page.on('console', (m) => { if (m.type() === 'error') { console.log(`${name}: CONSOLE ${m.text()}`); problems++; } });
  page.on('requestfailed', (r) => { console.log(`${name}: MISSING ${decodeURI(r.url())}`); problems++; });
  await page.addInitScript((d) => { window.SCREENS = d; }, SCREENS);
  await page.goto('file://' + path.join(HERE, `${name}.html`));
  let res;
  try {
    res = await page.evaluate(async (q) => ({ ...(await window.ready(q)), allow: window.ALLOW || [] }), qrsvg);
  } catch (e) {
    console.log(`${name}: FAILED ${e.message.split('\n')[0]}`); problems++;
    await page.close(); continue;
  }
  if (thrown) { console.log(`${name}: not captured`); await page.close(); continue; }
  const { groups, obox, allow = [] } = res;
  const ok = (a, b) => allow.includes(`${a}|${b}`) || allow.includes(`${b}|${a}`);
  // 1. inside each group, axis-aligned boxes in that group's own coordinates
  for (const [g, boxes] of Object.entries(groups)) {
    const names = Object.keys(boxes);
    for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) {
      const [a, b] = [boxes[names[i]], boxes[names[j]]];
      const ix = Math.min(a[2], b[2]) - Math.max(a[0], b[0]), iy = Math.min(a[3], b[3]) - Math.max(a[1], b[1]);
      if (ix > 0 && iy > 0 && !ok(names[i], names[j])) { console.log(`${name}: OVERLAP in ${g}: ${names[i]} x ${names[j]} (${ix}x${iy})`); problems++; }
    }
  }
  // 2. on the poster: page-level boxes and rotated objects, with SAT
  const polys = {};
  for (const [k, b] of Object.entries(groups.poster || {})) polys[k] = { p: corners({ cx: (b[0] + b[2]) / 2, cy: (b[1] + b[3]) / 2, w: b[2] - b[0], h: b[3] - b[1], r: 0 }), bleed: false };
  for (const [k, o] of Object.entries(obox)) polys[k] = { p: corners(o), bleed: !!o.bleed };
  const pn = Object.keys(polys);
  for (let i = 0; i < pn.length; i++) for (let j = i + 1; j < pn.length; j++) {
    const d = satOverlap(polys[pn[i]].p, polys[pn[j]].p);
    if (d > 0 && !ok(pn[i], pn[j])) { console.log(`${name}: OVERLAP ${pn[i]} x ${pn[j]} (${d.toFixed(1)}px deep)`); problems++; }
  }
  for (const [k, { p, bleed }] of Object.entries(polys)) {
    if (bleed) continue;
    const xs = p.map((c) => c[0]), ys = p.map((c) => c[1]);
    if (Math.min(...xs) < MX || Math.max(...xs) > W - MX || Math.min(...ys) < MT || Math.max(...ys) > H - MB) {
      console.log(`${name}: MARGIN ${k} x ${Math.min(...xs).toFixed(0)}..${Math.max(...xs).toFixed(0)} y ${Math.min(...ys).toFixed(0)}..${Math.max(...ys).toFixed(0)}`); problems++;
    }
  }
  await page.screenshot({ path: path.join(out, `${name}.png`) });
  fs.writeFileSync(path.join(out, `${name}-boxes.json`), JSON.stringify({ groups, obox }, null, 1));
  await page.close();
  console.log(`${name}: captured at ${W * scale}x${H * scale}`);
}
await browser.close();
console.log(problems ? `${problems} problem(s)` : 'no overlaps, margins ok');
process.exit(problems ? 1 : 0);
