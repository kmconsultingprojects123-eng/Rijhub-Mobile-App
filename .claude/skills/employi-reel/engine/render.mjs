// Capture the reel with headless Chrome.
//
//   node render.mjs stills OUT_DIR t1 t2 ...     one PNG per time (seconds)
//   node render.mjs frames OUT_DIR [FROM TO]     sub-frames for blur.py
//
// Sub-frames sample a 180-degree shutter: N instants spread over half a
// frame interval, centred on the frame's own time; blur.py averages them in
// linear light. N follows the motion: 20 on fast moves (fewer strobes into
// separate copies instead of a streak), 10 on medium ones, 3 at rest.
import fs from 'node:fs';
import path from 'node:path';
import { openStage, missing } from './stage.mjs';

const [mode, out, ...rest] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const { browser, page, cfg } = await openStage();
if (process.env.SAFE) await page.evaluate(() => { window.DEBUG_SAFE = true; });

const shot = async (t, file, type = 'png') => {
  await page.evaluate((tt) => window.render(tt), t);
  await page.screenshot(type === 'png' ? { path: file } : { path: file, type: 'jpeg', quality: 95 });
};

if (mode === 'stills') {
  for (const s of rest) {
    const t = Number(s);
    await shot(t, path.join(out, `t${t.toFixed(2).padStart(5, '0')}.png`));
  }
} else if (mode === 'frames') {
  const C = cfg.cues;
  const from = Number(rest[0] ?? 0), to = Number(rest[1] ?? C.total);
  const fast = (f) => C.arrive.some((a, k) => k > 0 && f >= a - C.dur[k] - 1 && f <= a + 2) || (f >= C.pull[0] - 2 && f < C.pull[1] + 3);
  const spans = [[C.cats[0], C.cats[0] + 24], [C.cats[1], C.cats[1] + 14], [C.fly[0] - 2, C.badge + 10], [C.stock, C.price + 10],
                 [C.chipsOut, C.chipsOut + 12], [C.flood[0] - 4, C.park[1] + 4], [C.pay[0] - 2, C.payChip + 10], [C.payOut, C.card[1] + 2],
                 [C.card[2], C.wipe[1] + 2], [C.endPhone[0], C.endPhone[1] + 4], [C.logo, C.badges[1] + 12],
                 [C.s3bg[0] - 1, C.s3bg[1] + 3], [C.added - 1, C.added + 14]];
  const subFor = (f) => (fast(f) ? 20 : spans.some(([a, b]) => f >= a && f < b) ? 10 : 3);
  // merge with any earlier schedule, so partial re-renders keep the rest
  const sp = path.join(out, 'subs.json');
  const sched = fs.existsSync(sp) ? JSON.parse(fs.readFileSync(sp, 'utf8')) : {};
  for (let f = from; f < to; f++) sched[f] = subFor(f);
  fs.writeFileSync(sp, JSON.stringify(sched));
  const t0 = Date.now();
  for (let f = from; f < to; f++) {
    const sub = sched[f];
    for (let s = 0; s < sub; s++) {
      const off = sub === 1 ? 0 : (s / (sub - 1) - 0.5) * 0.5;
      await shot(Math.max(0, (f + off) / 30), path.join(out, `f${String(f).padStart(4, '0')}_${s}.jpg`), 'jpeg');
    }
    if ((f - from) % 60 === 59) console.log(`frame ${f + 1}/${to}  ${((Date.now() - t0) / 1000 / (f - from + 1)).toFixed(2)}s/frame`);
  }
}
const miss = await missing(page);
if (miss.length) {
  console.log(`MISSING MEDIA (${miss.length}), drawn as placeholders:`);
  for (const m of miss.slice(0, 20)) console.log('  ', m);
  if (miss.length > 20) console.log(`   ...and ${miss.length - 20} more`);
  process.exitCode = 3;
}
await browser.close();
