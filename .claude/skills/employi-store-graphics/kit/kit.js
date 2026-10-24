'use strict';
// Shared pieces for the store graphics. A concept page builds into #canvas,
// tags its information elements with data-box (text, popped-out UI, chips),
// and render.mjs calls window.ready(), which waits for type and images, runs
// the page's layout(), and returns those boxes so overlaps and margins can be
// checked before anything is captured.

const CANVAS = document.getElementById('canvas');
const SCREEN = { w: 1320, h: 2868, border: 46 }; // the capture, and frame + bezel round it
const BODY = { w: SCREEN.w + 2 * SCREEN.border, h: SCREEN.h + 2 * SCREEN.border };

function el(cls, html, parent = CANVAS, tag = 'div') {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html != null) n.innerHTML = html;
  parent.appendChild(n);
  return n;
}
function css(n, o) { Object.assign(n.style, o); return n; }

/** An iPhone 17 Pro Max showing `src` (a 1320x2868 capture). */
function phone(src, parent = CANVAS) {
  const n = el('phone', '<div class="p-shadow"></div><div class="p-body"></div><div class="p-bezel"></div>'
    + '<div class="p-btn l action"></div><div class="p-btn l volup"></div><div class="p-btn l voldn"></div>'
    + '<div class="p-btn r side"></div><div class="p-btn r cam"></div>'
    + `<div class="p-screen"><img src="${src}"></div><div class="p-glare"></div>`, parent);
  n.dataset.src = src;
  return n;
}

/** Centre the phone's body on (cx, cy), `w` wide, turned `r` degrees. */
function place(ph, cx, cy, w, r = 0) {
  const s = w / BODY.w;
  ph.style.transform = `translate(${cx}px, ${cy}px) rotate(${r}deg) scale(${s}) translate(${-BODY.w / 2}px, ${-BODY.h / 2}px)`;
  ph._place = { cx, cy, s, r };
  return ph;
}

/** Where a point of the capture (in its own pixels) lands on the canvas. */
function onCanvas(ph, sx, sy) {
  const { cx, cy, s, r } = ph._place;
  const x = (sx + SCREEN.border - BODY.w / 2) * s, y = (sy + SCREEN.border - BODY.h / 2) * s;
  const a = (r * Math.PI) / 180;
  return [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)];
}

/**
 * A piece of the capture lifted off the screen. `rect` is [x, y, w, h] in
 * the capture's pixels; the piece is drawn `scale` times larger with its top
 * left corner at (x, y) on the canvas, turned `rot` degrees round its centre.
 */
function pop(src, rect, { x, y, scale = 1, rot = 0, radius = 0, shadow = '', parent = CANVAS, name = null }) {
  const [rx, ry, rw, rh] = rect;
  const n = el('pop', null, parent);
  css(n, {
    left: '0px', top: '0px', width: `${rw}px`, height: `${rh}px`,
    backgroundImage: `url("${src}")`, backgroundSize: `${SCREEN.w}px ${SCREEN.h}px`,
    backgroundPosition: `${-rx}px ${-ry}px`, borderRadius: typeof radius === 'number' ? `${radius}px` : radius,
    boxShadow: shadow,
    transformOrigin: '50% 50%',
    transform: `translate(${x + (rw * scale - rw) / 2}px, ${y + (rh * scale - rh) / 2}px) rotate(${rot}deg) scale(${scale})`,
  });
  if (name) obox(name, x + (rw * scale) / 2, y + (rh * scale) / 2, rw * scale, rh * scale, rot);
  return n;
}

// Information elements: anything with data-box is measured on the canvas as
// an axis-aligned box; rotated objects register an oriented box with obox().
// render.mjs fails on overlaps (unless allowed) and on text outside the
// margins, so a layout can't quietly lose a word under a phone.
const OBOX = {};
function obox(name, cx, cy, w, h, r = 0, opts = {}) { OBOX[name] = { cx, cy, w, h, r, ...opts }; }

/** Shrinks a line's type until it fits `maxW`. */
function fit(n, maxW) {
  const w = n.getBoundingClientRect().width;
  if (w > maxW) n.style.fontSize = `${(parseFloat(getComputedStyle(n).fontSize) * maxW) / w}px`;
}

// Seeded randomness, so a page renders the same every time.
let SEED = 7;
const rnd = () => ((SEED = (SEED * 16807) % 2147483647) / 2147483647);

window.ready = async () => {
  for (const w of [400, 500, 600, 700, 800, 900]) await document.fonts.load(`${w} 100px Inter`, 'Say ₦');
  await document.fonts.ready;
  await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
  if (window.layout) await window.layout();
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const boxes = {};
  document.querySelectorAll('[data-box]').forEach((n) => {
    const b = n.getBoundingClientRect();
    boxes[n.dataset.box] = { cx: (b.left + b.right) / 2, cy: (b.top + b.bottom) / 2, w: b.width, h: b.height, r: 0, text: n.dataset.text !== 'no' };
  });
  for (const [k, o] of Object.entries(OBOX)) boxes[k] = { text: false, ...o };
  return { boxes, allow: window.ALLOW || [], size: window.SIZE || [1320, 2868], margin: window.MARGIN || 64 };
};

// ── devices for every store slot ───────────────────────────────────────────
// Each is built round its capture at native size: the screen, the bezel and
// the frame, its buttons as fractions of the body, then scaled into place
// with place(). Frames are dark with a lit hairline edge on every device.
const DEVICES = {
  iphone: { w: 1320, h: 2868, border: 46, inset: 15, screenR: 190, bodyR: 236,
    buttons: [['l', 0.19, 0.05], ['l', 0.27, 0.085], ['l', 0.375, 0.085], ['r', 0.305, 0.128], ['r', 0.567, 0.084, 0.7]] },
  ipad: { w: 2064, h: 2752, border: 92, inset: 18, screenR: 70, bodyR: 162,
    buttons: [['t', 0.80, 0.07], ['r', 0.09, 0.05], ['r', 0.15, 0.05]] },
  android: { w: 1080, h: 2400, border: 40, inset: 12, screenR: 104, bodyR: 144, hole: [540, 46, 21],
    buttons: [['r', 0.24, 0.07], ['r', 0.34, 0.12]] },
  tablet: { w: 1600, h: 2560, border: 86, inset: 16, screenR: 56, bodyR: 142,
    buttons: [['t', 0.78, 0.07], ['r', 0.1, 0.07]] },
};

/** A device of `kind` showing `src`, its capture at the device's native size. */
function device(src, kind) {
  const d = DEVICES[kind], W = d.w + 2 * d.border, H = d.h + 2 * d.border;
  const n = el('dev', null);
  css(n, { position: 'absolute', left: '0px', top: '0px', width: `${W}px`, height: `${H}px`, transformOrigin: '0 0' });
  const part = (style) => css(el('', null, n), { position: 'absolute', ...style });
  part({ inset: `${0.02 * H}px ${0.03 * W}px ${-0.008 * H}px`, borderRadius: `${d.bodyR}px`, background: 'rgba(40, 25, 15, .5)', filter: `blur(${0.025 * W}px)`, transform: `translateY(${0.018 * H}px)` });
  const t = Math.max(8, Math.round(W * 0.0085));
  for (const [side, at, len, thin = 1] of d.buttons) {
    const along = side === 't' ? W : H, size = Math.round(len * along);
    const g = side === 'l' ? '90deg' : side === 'r' ? '270deg' : '180deg';
    const b = part({ borderRadius: `${t}px`, background: `linear-gradient(${g}, #6d6f74, #2b2c30 60%, #1a1b1e)` });
    if (side === 't') css(b, { top: `${-t * 0.7}px`, left: `${at * W}px`, width: `${size}px`, height: `${t * thin}px` });
    else css(b, { [side === 'l' ? 'left' : 'right']: `${-t * 0.7}px`, top: `${at * H}px`, width: `${t * thin}px`, height: `${size}px` });
  }
  part({ inset: '0', borderRadius: `${d.bodyR}px`,
    background: 'linear-gradient(128deg, #8a8c91 0%, #3a3b3f 9%, #1c1d20 30%, #15161a 52%, #222328 74%, #45474c 91%, #8f9196 100%)',
    boxShadow: 'inset 0 0 0 2px rgba(255,255,255,.28), inset 0 0 0 6px rgba(0,0,0,.55), inset 0 0 0 9px rgba(255,255,255,.06)' });
  part({ inset: `${d.inset}px`, borderRadius: `${d.bodyR - d.inset}px`, background: '#050506', boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,.07)' });
  const screen = part({ left: `${d.border}px`, top: `${d.border}px`, width: `${d.w}px`, height: `${d.h}px`, borderRadius: `${d.screenR}px`, overflow: 'hidden', background: '#fff' });
  css(el('', null, screen, 'img'), { position: 'absolute', left: '0px', top: '0px', width: `${d.w}px`, height: `${d.h}px`, display: 'block' }).src = src;
  if (d.hole) {
    const [hx, hy, hr] = d.hole;
    part({ left: `${d.border + hx - hr}px`, top: `${d.border + hy - hr}px`, width: `${2 * hr}px`, height: `${2 * hr}px`, borderRadius: '50%', background: 'radial-gradient(circle at 40% 38%, #2a2f3a 0%, #07080a 60%)', boxShadow: '0 0 0 3px #0b0b0d' });
  }
  part({ left: `${d.border}px`, top: `${d.border}px`, width: `${d.w}px`, height: `${d.h}px`, borderRadius: `${d.screenR}px`,
    background: 'linear-gradient(112deg, rgba(255,255,255,.10) 0%, rgba(255,255,255,.035) 22%, rgba(255,255,255,0) 38%)' });
  n._dev = { kind, W, H, border: d.border };
  return n;
}

/** Places a device()'s body: centre (cx, cy), `w` wide. Returns its box. */
function placeDevice(n, cx, cy, w) {
  const { W, H } = n._dev, s = w / W;
  n.style.transform = `translate(${cx}px, ${cy}px) scale(${s}) translate(${-W / 2}px, ${-H / 2}px)`;
  n._place = { cx, cy, s, r: 0 };
  return { x: cx - w / 2, y: cy - (H * s) / 2, w, h: H * s };
}

/** Where a point of a device's capture lands on the canvas. */
function onDevice(n, sx, sy) {
  const { W, H, border } = n._dev, { cx, cy, s } = n._place;
  return [cx + (sx + border - W / 2) * s, cy + (sy + border - H / 2) * s];
}
