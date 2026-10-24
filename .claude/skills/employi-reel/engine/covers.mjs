// Reel covers, composed from the reel's own scenes.
//
//   node covers.mjs OUT_DIR
//
//   cover.jpg      the value scene: the big line and its chip, held at rest
//   cover-alt.jpg  the reveal: the phone and the categories on the lit wall
//
// Both carry the logo on a white plate (logos are drawn for light grounds;
// never recolour or redraw one), and everything that matters sits inside
// the profile grid's centred 3:4 crop (1080 x 1440, y 240-1680), so one
// file works full screen in the Reels tab and cropped on the grid.
import fs from 'node:fs';
import path from 'node:path';
import { openStage } from './stage.mjs';

const out = process.argv[2];
fs.mkdirSync(out, { recursive: true });

const addLogo = (page, top, h) => page.evaluate(async ({ top, h }) => {
  const plate = document.createElement('div');
  plate.style.cssText = `position:absolute;left:50%;top:${top}px;transform:translateX(-50%);background:#fff;border-radius:999px;
    padding:${Math.round(h * .22)}px ${Math.round(h * .5)}px;box-shadow:0 18px 44px rgba(1,15,28,.28);display:flex;align-items:center;z-index:50`;
  plate.innerHTML = window.makeLogo(h);
  document.getElementById('stage').appendChild(plate);
  await Promise.all([...plate.querySelectorAll('img')].map((i) => i.decode().catch(() => {})));
}, { top, h });

{ // cover: the value scene
  const { browser, page } = await openStage();
  await page.evaluate(async () => {
    const C = window.CUES;
    await window.render(((window.REEL.place ? C.payOut : C.wipe[0] - 4) - 12) / 30);
    document.getElementById('valueBig').style.top = '500px';
    document.getElementById('valueChip').style.top = '930px';
  });
  await addLogo(page, 292, 92);
  await page.screenshot({ path: path.join(out, 'cover.jpg'), type: 'jpeg', quality: 95 });
  await browser.close();
}
{ // cover-alt: the reveal on the lit wall
  const { browser, page } = await openStage();
  await page.evaluate(async () => {
    const C = window.CUES;
    await window.render((C.cats[1] - 6) / 30);
    const $ = (id) => document.getElementById(id);
    const s3 = $('s3bg'); s3.classList.remove('hide'); s3.style.clipPath = 'none'; s3.style.opacity = 1;
    $('litEdge').classList.add('hide'); $('pegDark').style.opacity = 0;
    $('pglow').style.opacity = 0.35;
    s3.querySelector('.lamp').style.display = 'none';
    // the bokeh are only placed once the lit-wall scene runs; on this
    // earlier frame they would all sit stacked in the top-left corner
    s3.querySelectorAll('.bokeh').forEach((el) => { el.style.display = 'none'; });
    const ph = $('phone');
    ph.style.transform = ph.style.transform.replace(/translate3d\(([-\d.]+)px, ([-\d.]+)px/, (m, x, y) => `translate3d(${x}px, ${Number(y) + 150}px`)
                                           .replace(/scale\(([\d.]+)\)/, 'scale(0.86)');
    document.querySelectorAll('.catcard').forEach((c) => { c.style.top = `${parseFloat(c.style.top) + 110}px`; });
    const head = $('revealHead');
    head.style.top = '430px';
    head.querySelectorAll('div').forEach((d) => { d.style.opacity = 1; d.style.filter = 'none'; d.style.transform = 'none'; });
    head.children[0].style.fontSize = '56px';
    head.children[0].style.textShadow = '0 4px 18px rgba(1,30,48,.45)';
    head.children[1].style.fontSize = '100px';
    head.children[1].style.textShadow = '0 6px 26px rgba(1,30,48,.40)';
    // the highlighted word gets the caption treatment, accent on a white
    // plate: a pale highlight colour vanished into the lit wall
    const hl = head.querySelector('.hl');
    if (hl) hl.style.cssText = 'display:inline-block;background:#fff;color:var(--accent);padding:0 26px 10px;border-radius:24px;text-shadow:none;box-shadow:0 14px 34px rgba(1,15,28,.25);margin-left:8px';
  });
  await addLogo(page, 286, 84);
  await page.screenshot({ path: path.join(out, 'cover-alt.jpg'), type: 'jpeg', quality: 95 });
  await browser.close();
}
console.log('covers written to', out);
