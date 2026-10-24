// The reel, as a pure function of time.
//
// render(t) sets the whole stage for second t, so any frame or sub-frame
// renders identically in any order. Three inputs, injected by stage.mjs:
//
//   window.BRAND  brand.json  colours, type, logo, badges, the wall pattern
//   window.REEL   reel.json   the story: photos, copy, chips, recordings
//   window.CUES   cues.json   timing, in frames at 30 fps (120 BPM = 15 a beat),
//                             shared with the sub-frame scheduler and the sound
//
// The motion lives here and nowhere else; a new reel is new data, not new code.

const B = window.BRAND, R = window.REEL, C = window.CUES;
const FPS = C.fps, W = 1080, H = 1920;
const $ = (id) => document.getElementById(id);
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const P = (f, f0, f1) => clamp((f - f0) / (f1 - f0));
const E = {
  inOutCubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  inOutQuart: (t) => (t < 0.5 ? 8 * t ** 4 : 1 - Math.pow(-2 * t + 2, 4) / 2),
  outCubic: (t) => 1 - Math.pow(1 - t, 3),
  outQuint: (t) => 1 - Math.pow(1 - t, 5),
  inCubic: (t) => t * t * t,
  outBack: (t, s = 1.70158) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2),
};
// Damped spring step response, 0 -> 1 with natural overshoot. fr in frames.
const spring = (fr, freq = 2.0, damp = 6.5) => {
  if (fr <= 0) return 0;
  const t = fr / FPS;
  return 1 - Math.exp(-damp * t) * Math.cos(2 * Math.PI * freq * t);
};
const css = (el, o) => { for (const k in o) el.style[k] = o[k]; };
const show = (el, on) => el.classList.toggle('hide', !on);
const K = B.colors;

// ── brand: CSS variables, the typeface, the wall pattern ───────────────────
(function applyBrand() {
  const vars = {
    '--ink': K.ink, '--accent': K.accent, '--accent-deep': K.accentDeep, '--accent-rgb': K.accentRGB, '--hl': K.hl,
    '--tint': K.tint, '--muted': K.muted, '--muted-2': K.muted2, '--chip-ring': K.chipRing,
    '--stage-bg': K.stageBg, '--bg': K.bg, '--wall-lit': K.wallLit, '--flood': K.flood, '--end-bg': K.endBg,
    '--tag-sale': K.tagSale, '--badge': K.badge, '--lamp-a': K.lamp[0], '--lamp-b': K.lamp[1],
    '--lit-edge': K.litEdge[0], '--lit-glow': K.litEdge[1], '--wire-a': K.wire[0], '--wire-b': K.wire[1],
    '--pin-mid': K.peg[0], '--pin-lo': K.peg[1], '--pt': B.tightPunct || 0,
  };
  const rules = [':root{' + Object.entries(vars).map(([k, v]) => `${k}:${v}`).join(';') + '}'];
  for (const [w, file] of Object.entries(B.font.files)) rules.push(`@font-face{font-family:P;src:url("${file}");font-weight:${w};}`);
  const st = document.createElement('style');
  st.textContent = rules.join('\n');
  document.head.appendChild(st);
  $('stage').classList.add(`wall-${B.wall || 'pegboard'}`);
})();

// A price: the brand's own currency sign, or one drawn from N with two bars
// when the typeface lacks it (Poppins has no ₦).
const money = (n) => (B.currency.draw ? `<span class="cur">N<i></i><i></i></span>` : B.currency.symbol) + Number(n).toLocaleString('en-US');
// *word* marks emphasis in copy: the highlight colour on dark grounds,
// the accent on light ones.
const fmt = (s, cls) => pt(s).replace(/\*([^*]+)\*/g, `<span class="${cls}">$1</span>`);
// Optical punctuation for display lines: some typefaces (Plus Jakarta Sans at
// 800) set a full stop so loose that "love." reads "love ."; brand.json's
// tightPunct (em) pulls stops and commas in after a letter. Off when unset.
function pt(s) { return B.tightPunct ? s.replace(/([A-Za-z\u00C0-\u024F])([.,])/g, '$1<span class="pt">$2</span>') : s; }

// ── icons (24-unit line icons, drawn here) ─────────────────────────────────
const sv = (c, body, w = 2.1) => `<svg viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
const ICON = {
  cart: (c) => sv(c, '<circle cx="9.5" cy="20" r="1.5"/><circle cx="17.5" cy="20" r="1.5"/><path d="M2.5 3.5h2.4l2.5 11.4c.15.75.8 1.3 1.6 1.3h8.4c.75 0 1.4-.5 1.6-1.25L21 8H6"/>'),
  check: (c) => sv(c, '<path d="M5 12.5l4.5 4.5L19 7.5"/>', 2.8),
  tag: (c) => sv(c, '<path d="M3 12.2V4.5c0-.8.7-1.5 1.5-1.5h7.7l8.8 8.8-9.2 9.2z"/><circle cx="7.8" cy="7.8" r="1.6"/>'),
  box: (c) => sv(c, '<path d="M21 7.8l-9-4.8-9 4.8v8.4l9 4.8 9-4.8z"/><path d="M3 7.8l9 4.9 9-4.9M12 12.7V21"/>'),
  truck: (c) => sv(c, '<path d="M2.5 6.5h11v9h-11z"/><path d="M13.5 9.5h4.2l3.3 3.6v2.4h-7.5"/><circle cx="7" cy="17.5" r="2"/><circle cx="17.2" cy="17.5" r="2"/>'),
  cash: (c) => sv(c, '<rect x="2.5" y="6.5" width="19" height="11" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6 10v4M18 10v4"/>'),
  store: (c) => sv(c, '<path d="M4.5 11v9h15v-9"/><path d="M3 9.5L5 4h14l2 5.5"/><path d="M3 9.5a2.25 2.25 0 0 0 4.5 0 2.25 2.25 0 0 0 4.5 0 2.25 2.25 0 0 0 4.5 0 2.25 2.25 0 0 0 4.5 0"/><path d="M10 20v-5h4v5"/>'),
  basket: (c) => sv(c, '<path d="M4 9.5h16l-1.6 9.2c-.13.75-.78 1.3-1.55 1.3H7.15c-.77 0-1.42-.55-1.55-1.3z"/><path d="M8.5 9.5L11 4M15.5 9.5L13 4M2.5 9.5h19"/><path d="M9.5 13v3.5M14.5 13v3.5"/>'),
  cookie: (c) => sv(c, `<circle cx="12" cy="12" r="9"/><circle cx="9" cy="9.5" r="1.1" fill="${c}" stroke="none"/><circle cx="14.6" cy="8.6" r="1.1" fill="${c}" stroke="none"/><circle cx="15.2" cy="14.2" r="1.1" fill="${c}" stroke="none"/><circle cx="9.6" cy="15.2" r="1.1" fill="${c}" stroke="none"/>`),
  bowl: (c) => sv(c, '<path d="M3 11.5h18a9 9 0 0 1-18 0z"/><path d="M8.5 20.5h7"/><path d="M9.5 8.2c0-1.4 1-1.9 1-3.4M13.5 8.2c0-1.4 1-1.9 1-3.4"/>'),
  plug: (c) => sv(c, '<path d="M9 3v5M15 3v5"/><path d="M6.5 8h11v3.5a5.5 5.5 0 0 1-11 0z"/><path d="M12 17v4.5"/>'),
  home: (c) => sv(c, '<path d="M3.5 11L12 4l8.5 7"/><path d="M5.5 9.5V20h13V9.5"/><path d="M10 20v-5.5h4V20"/>'),
  plot: (c) => sv(c, '<path d="M3 7l6-3 6 3 6-3v13l-6 3-6-3-6 3z"/><path d="M9 4v13M15 7v13"/>'),
  key: (c) => sv(c, '<circle cx="8" cy="15" r="4.5"/><path d="M11.2 11.8L20 3M16.5 6.5l2.5 2.5M14.5 8.5l2 2"/>'),
  office: (c) => sv(c, '<rect x="4.5" y="3" width="15" height="18" rx="1"/><path d="M8.5 7h2M13.5 7h2M8.5 11h2M13.5 11h2M8.5 15h2M13.5 15h2M10.5 21v-3h3v3"/>'),
  calendar: (c) => sv(c, '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/><path d="M8 13.5h2M14 13.5h2M8 17h2"/>'),
  shield: (c) => sv(c, '<path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.3-7.5 9.5-4.3-1.2-7.5-4.9-7.5-9.5V6z"/><path d="M8.6 12.2l2.4 2.4 4.4-4.6"/>'),
  pin: (c) => sv(c, '<path d="M12 21s-6.5-6.2-6.5-11.2a6.5 6.5 0 0 1 13 0C18.5 14.8 12 21 12 21z"/><circle cx="12" cy="9.8" r="2.4"/>'),
  chat: (c) => sv(c, '<path d="M20.5 12a7.5 7.5 0 0 1-11 6.6L4 20l1.4-4.8A7.5 7.5 0 1 1 20.5 12z"/>'),
  // trades (added for Employi's categories; unused by the other brands)
  snow: (c) => sv(c, '<path d="M12 21L12 3M4.2 16.5L19.8 7.5M4.2 7.5L19.8 16.5M14.1 4.5L12 6.6L9.9 4.5M19.5 10.1L16.7 9.3L17.4 6.5M17.4 17.5L16.7 14.7L19.5 13.9M9.9 19.5L12 17.4L14.1 19.5M4.5 13.9L7.3 14.7L6.6 17.5M6.6 6.5L7.3 9.3L4.5 10.1"/>', 1.9),
  drop: (c) => sv(c, '<path d="M12 3.5c-3 3.9-6 7.6-6 10.7a6 6 0 0 0 12 0c0-3.1-3-6.8-6-10.7z"/><path d="M9.3 14.6a2.8 2.8 0 0 0 2.5 2.8"/>'),
  wrench: (c) => sv(c, '<path d="M14.6 6.4a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.1-3.1a5.6 5.6 0 0 1-7.4 7.4l-6.6 6.6a2 2 0 0 1-2.8-2.8l6.6-6.6a5.6 5.6 0 0 1 7.4-7.4z"/>'),
};

// ── missing media: shown, never blank ──────────────────────────────────────
// A missing file used to render as nothing at all: the phone screen went
// white for every sub-frame that asked for one, and only the blurred video
// showed it. Now a missing file draws a labelled placeholder, and every
// path is listed in window.MISSING for render.mjs to report.
window.MISSING = new Set();
const PH_CACHE = {};
function placeholder(label, w = 1080, h = 1920) {
  const key = `${label}|${w}x${h}`;
  if (PH_CACHE[key]) return PH_CACHE[key];
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d');
  const grd = g.createLinearGradient(0, 0, 0, h); grd.addColorStop(0, K.tint); grd.addColorStop(1, '#FFFFFF');
  g.fillStyle = grd; g.fillRect(0, 0, w, h);
  g.strokeStyle = K.accent; g.lineWidth = Math.max(4, w / 180); g.setLineDash([w / 40, w / 60]);
  g.strokeRect(w * 0.04, w * 0.04, w * 0.92, h - w * 0.08);
  g.fillStyle = K.accentDeep; g.textAlign = 'center';
  g.font = `800 ${Math.round(w * 0.075)}px P`; g.fillText('PLACEHOLDER', w / 2, h / 2 - w * 0.04);
  g.font = `600 ${Math.round(w * 0.045)}px P`;
  const words = String(label).split(/\s+/); let line = '', y = h / 2 + w * 0.05;
  for (const wd of words) {
    if (g.measureText(`${line} ${wd}`).width > w * 0.8 && line) { g.fillText(line, w / 2, y); line = wd; y += w * 0.06; }
    else line = line ? `${line} ${wd}` : wd;
  }
  g.fillText(line, w / 2, y);
  return (PH_CACHE[key] = c.toDataURL('image/jpeg', 0.9));
}
const media = (img, src, slot) => { img.dataset.slot = slot; img.src = src; return img; };
async function settle(img) {
  if (!img.getAttribute('src') || img.src.startsWith('data:')) return;
  try { await img.decode(); } catch {
    window.MISSING.add(img.getAttribute('src'));
    img.src = placeholder(img.dataset.slot || img.getAttribute('src'));
    await img.decode().catch(() => {});
  }
}

// ── the hook: photos swiped like reels ─────────────────────────────────────
const SHOTS = R.hook.photos, ARRIVE = C.arrive, DUR = C.dur, LAST = SHOTS.length - 1;
if (ARRIVE.length !== SHOTS.length) console.error(`cues.arrive has ${ARRIVE.length} entries, reel.json hook.photos has ${SHOTS.length}: they must match`);

function shelfPos(f) {
  for (let k = 1; k < ARRIVE.length; k++) {
    const a = ARRIVE[k], d = DUR[k];
    if (f < a - d) return k - 1;
    if (f < a) {
      const p = (f - (a - d)) / d;
      return k - 1 + (k === LAST ? E.outCubic(p) : E.inOutCubic(p));
    }
  }
  return LAST;
}

// ── the phone ──────────────────────────────────────────────────────────────
const PH = { w: 655, h: 1350.5, sx: 27.5, sy: 23, sw: 600, shh: 1304.5 };
PH.cx = PH.w / 2; PH.cy = PH.h / 2;
// The hook's last photo lands on its own card inside the app recording:
// that card's rectangle in the recording, as fractions of the frame.
const CARD = R.reveal.card;
const cardLocal = {
  x: PH.sx + CARD.x0 * PH.sw, y: PH.sy + CARD.y0 * PH.shh,
  w: (CARD.x1 - CARD.x0) * PH.sw, h: (CARD.y1 - CARD.y0) * PH.shh,
};
cardLocal.cx = cardLocal.x + cardLocal.w / 2; cardLocal.cy = cardLocal.y + cardLocal.h / 2;
const CARD_OFF = { x: cardLocal.cx - PH.cx, y: cardLocal.cy - PH.cy };
const REST = { cx: 540, cy: 1150, s: 1.0 };
const S0 = H / cardLocal.h;                                // card fills the frame height

// Recording frames over time. Each segment is [from, firstFrame, rate, maxFrame?];
// "from" is a frame number or a cue path such as "rec.grid". Always floored:
// a fractional sub-frame time must never ask for a frame like 43.25.jpg.
const cueVal = (ref) => (typeof ref === 'number' ? ref : ref.split('.').reduce((o, k) => o[k], C));
function segFrame(segs, f) {
  let cur = segs[0];
  for (const s of segs) if (f >= cueVal(s[0])) cur = s;
  const [at, first, rate, max] = cur;
  let n = rate === 0 ? first : first + Math.floor((f - cueVal(at)) * rate);
  if (max != null) n = Math.min(max, n);
  return Math.max(1, n);
}
function recSrc(f) {
  const rec = f >= C.wipe[0] ? R.recordings.end : R.recordings.shop;
  return { src: `${rec.dir}/${String(segFrame(rec.segments, f)).padStart(4, '0')}.jpg`, slot: `app recording: ${rec.dir}` };
}

const PLACE = R.place || null;                            // the "in store" scene is optional
const EXIT = PLACE ? C.phoneExit : [C.wipe[0], C.wipe[0] + 18];
const VALUE_OUT = PLACE ? C.payOut : C.wipe[0] - 4;

function phoneState(f) {
  const [p0, p1] = C.pull;
  if (f < p1) {
    const e = E.inOutQuart(P(f, p0, p1));
    const s = Math.exp(lerp(Math.log(S0), Math.log(REST.s), e));
    const c0 = { x: 540, y: 960 };
    const c1 = { x: REST.cx + REST.s * CARD_OFF.x, y: REST.cy + REST.s * CARD_OFF.y };
    const cc = { x: lerp(c0.x, c1.x, e), y: lerp(c0.y, c1.y, e) };
    return { cx: cc.x - s * CARD_OFF.x, cy: cc.y - s * CARD_OFF.y, s, rx: 0, ry: 0, rz: 0, cardC: cc };
  }
  if (f >= C.wipe[0]) {                                   // end card: rises, the second recording playing
    const up = E.outQuint(P(f, C.endPhone[0], C.endPhone[1]));
    return { cx: 540, cy: lerp(2700, 1905, up), s: 1.0, rx: lerp(18, 7, up), ry: lerp(-10, 5, E.inOutCubic(P(f, C.endPhone[0], C.total))), rz: 0 };
  }
  const drift = Math.sin((f - p1) / 40) * 6;
  let rx = lerp(0, 5, E.inOutCubic(P(f, p1, p1 + 44)));
  let ry = lerp(0, -8, E.inOutCubic(P(f, p1, 230))) + lerp(0, 14, E.inOutCubic(P(f, 230, C.flood[0])));
  let s = REST.s, cx = REST.cx, cy = REST.cy + drift, rz = 0;
  s *= 1 + 0.02 * Math.exp(-Math.max(0, f - C.tap2) / 5) * (f >= C.tap2 ? 1 : 0);   // a nudge on the tap
  const park = E.inOutCubic(P(f, C.park[0], C.park[1]));
  cy = lerp(cy, 1760 + Math.sin(f / 30) * 5 * park, park); s = lerp(s, 0.94, park);
  rx = lerp(rx, 14, park); ry = lerp(ry, 0, park);
  const out = E.inCubic(P(f, EXIT[0], EXIT[1]));
  cy += out * 1100; rx += out * 20;
  return { cx, cy, s, rx, ry, rz };
}

// ── build the DOM once ─────────────────────────────────────────────────────
const shelf = $('shelf');
const photos = SHOTS.map((p, j) => {
  const el = document.createElement('div');
  el.className = 'ph abs full';
  const was = p.was ? `<s>${money(p.was)}</s>` : '';
  const off = p.was ? `<div class="off">${Math.round((1 - p.price / p.was) * 100)}% OFF</div>` : '';
  const unit = p.unit ? `<span class="unit">${p.unit}</span>` : '';            // e.g. /year on a rental
  const price = p.price != null ? `<div class="tp">${money(p.price)}${unit}${off}</div>` : '';
  el.innerHTML = `<img><div class="tag${p.was ? ' sale' : ''}"><div class="hole"></div><div class="tl">${p.label}${was}</div>${price}</div>`;
  media(el.querySelector('img'), p.file, `hook photo ${j + 1}: ${p.label}`);
  shelf.appendChild(el);
  return { el, img: el.querySelector('img'), tag: el.querySelector('.tag'), p };
});

const text = $('text'), float = $('float');
const mk = (parent, cls, html) => { const d = document.createElement('div'); d.className = cls; d.innerHTML = html; parent.appendChild(d); return d; };
const capLine = (s) => (/^\*[^*]+\*$/.test(s) ? `<div class="cap acc">${pt(s.slice(1, -1))}</div>` : `<div class="cap">${fmt(s, 'acc-t')}</div>`);

const [capA, capB] = R.hook.captions.map((lines) => mk(text, 'caps', lines.map(capLine).join('')));
const head2 = mk(text, 'head', `<div class="l1">${pt(R.reveal.headline[0])}</div><div class="l2">${fmt(R.reveal.headline[1], 'hl')}</div>`);
head2.id = 'revealHead';
const head3a = mk(text, 'head', `<div class="l3">${pt(R.shop.headlines[0])}</div>`);
const head3b = mk(text, 'head', `<div class="l3">${pt(R.shop.headlines[1])}</div>`);
const pay = mk(text, 'big', R.value.lines.map((ln) => `<div>${ln.map((w) => `<span class="word">${pt(w)}</span>`).join(' ')}</div>`).join(''));
pay.id = 'valueBig';
const chip = mk(text, 'chip', `<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="22" fill="${K.accent}"/><path d="M14 24.5l6.5 6.5L34 17.5" stroke="#fff" stroke-width="4.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>${R.value.chip}`);
chip.id = 'valueChip';
const pick = mk(text, 'head', PLACE ? PLACE.headline.map((l) => `<div class="l2" style="font-size:104px">${fmt(l, 'hl')}</div>`).join('') : '');
const loc = mk(text, '', PLACE ? `<div style="position:relative;width:76px;height:96px"></div><div><div class="t1">${PLACE.location[0]}</div><div class="t2">${PLACE.location[1]}</div></div>` : '');
loc.id = 'loc';
const pin = mk(text, '', `<svg viewBox="0 0 92 120"><defs><linearGradient id="pg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${K.pin[0]}"/><stop offset="1" stop-color="${K.pin[1]}"/></linearGradient></defs>
  <path d="M46 4C24 4 8 20 8 41c0 27 38 71 38 71s38-44 38-71C84 20 68 4 46 4z" fill="url(#pg)"/><circle cx="46" cy="40" r="14" fill="#fff"/></svg>`);
pin.id = 'pin';
[capA, capB].forEach((c) => (c.style.top = '210px'));
head2.style.top = '200px'; head3a.style.top = '228px'; head3b.style.top = '228px';
pay.style.top = '470px'; pay.style.fontSize = '178px';
pick.style.top = '250px';
if (PLACE) media($('placeImg'), PLACE.photo, 'place photo');

// reveal: categories, as real photos on floating cards (optional)
const CATS = (R.reveal.categories || []).map((c) => {
  const el = mk(float, 'catcard', `<img><div class="lab"><div class="ic">${ICON[c.icon](K.icon)}</div><div class="tx">${c.label}</div></div>`);
  media(el.querySelector('img'), c.img, `category: ${c.label}`);
  return { ...c, el };
});

// shop: the floating UI. Three tags hang on the wall; the item flies into the bubble.
const mkHang = (html) => {
  const w = mk(float, 'hang', '<div class="wire"></div>');
  const c = document.createElement('div'); c.className = 'fchip'; c.innerHTML = html; w.appendChild(c);
  return { w, c, pin: mk(float, 'pegpin', '') };
};
const chipHTML = (c) => {
  const ic = c.solid ? `<div class="ic" style="background:${K.accent}">${ICON[c.icon]('#fff')}</div>`
                     : `<div class="ic" style="background:${K.tint}">${ICON[c.icon](K.icon)}</div>`;
  const main = c.price != null ? money(c.price) + (c.unit ? `<span class="unit">${c.unit}</span>` : '') : (c.text || '');
  return c.sub ? `${ic}<div class="two"><span class="pr">${main}</span><small>${c.sub}</small></div>` : `${ic}${main}`;
};
const HANG = [['stock', 190, 948, -1], ['price', 884, 1062, 1], ['added', 214, 1272, -1]];
const hangs = R.shop.chips.slice(0, 3).map((c, i) => ({ h: mkHang(chipHTML(c)), cue: HANG[i][0], x: HANG[i][1], y: HANG[i][2], side: HANG[i][3] }));
const cartb = mk(float, '', `${ICON[R.shop.bubble.icon](K.icon)}<div id="badge">${R.shop.bubble.badge}</div>`);
cartb.id = 'cartb';
const ghosts = Array.from({ length: 5 }, () => { const g = mk(float, 'ghost', '<img>'); media(g.querySelector('img'), R.shop.flyer, 'flying item'); return g; });
const flyer = mk(float, '', '<img>');
flyer.id = 'flyer';
media(flyer.querySelector('img'), R.shop.flyer, 'flying item');
const sparks = Array.from({ length: 12 }, (_, i) => { const s = mk(float, 'spark', ''); s.style.background = K.sparks[i % K.sparks.length]; return s; });

// soft bokeh lights drifting through the lit wall
const s3bg = $('s3bg');
const BOKEH = [[160, 420, 220], [900, 300, 160], [820, 1500, 260], [120, 1600, 180], [560, 1780, 140], [980, 980, 120]]
  .map(([x, y, r], i) => { const b = mk(s3bg, 'bokeh', ''); css(b, { width: `${r}px`, height: `${r}px`, background: K.bokeh[i % K.bokeh.length] }); return { b, x, y, r, i }; });

// end card
const end = $('end');
window.makeLogo = (h) => {                                 // the brand's logo at a given height
  const L = B.logo;
  if (L.type === 'image') return `<img src="${L.src}" style="height:${h}px;display:block">`;
  return `<div class="lockup"><img src="${L.mark}" style="height:${h}px;display:block">` +
    `<span style="font-size:${h * L.size}px;letter-spacing:${L.tracking}em;margin-left:${h * L.gap}px;color:${L.color || K.ink}">${L.text}</span></div>`;
};
$('logo').innerHTML = B.logo.type === 'image' ? `<img src="${B.logo.src}" style="width:${B.logo.width}px;display:block">` : window.makeLogo(B.logo.height);
$('endHead').innerHTML = R.end.headline.map((l) => fmt(l, 't')).join('<br>');
media($('bA'), B.badges.appStore, 'App Store badge');
media($('bG'), B.badges.googlePlay, 'Google Play badge');
const ECHIPS = R.end.chips.map(([ic, t]) => mk(end, 'echip', `<div class="ic">${ICON[ic](K.icon)}</div>${t}`));

// taps ride the phone's transform, so they live inside the screen
const screenEl = $('screen');
const mkIn = (cls) => { const d = document.createElement('div'); d.className = cls; screenEl.appendChild(d); return d; };
const TAPS = R.shop.taps.map((tp, i) => ({
  f: C[`tap${i + 1}`],
  x: tp.at === 'card' ? (CARD.x0 + CARD.x1) / 2 : tp.x,
  y: tp.at === 'card' ? (CARD.y0 + CARD.y1) / 2 : tp.y,
  r: mkIn('ripple'), d: mkIn('dot'),
}));

const morph = $('morph');
morph.innerHTML = '<img style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover">';
const morphImg = media(morph.querySelector('img'), R.reveal.morph, 'the hook\'s last photo, uncropped');

// ── render ─────────────────────────────────────────────────────────────────
const scr = $('scr');
let lastSrc = '';

window.ready = async () => {
  await Promise.all(Object.keys(B.font.files).map((w) => document.fonts.load(`${String(w).split(' ')[0]} 100px P`)));
  await document.fonts.ready;
  await Promise.all([...document.querySelectorAll('img')].map(settle));
};

const popIn = (fr, from = 0.6) => {        // spring scale + fade for a pop-in
  const sp = spring(fr, 2.2, 7.5);
  return { s: lerp(from, 1, sp), o: clamp(fr / 3), sp };
};

window.render = async (t) => {
  const f = t * FPS;

  // ── hook: the photo strip ───────────────────────────────────────────────
  const inHook = f < C.pull[0] + 1;
  show(shelf, inHook);
  if (inHook) {
    const s = shelfPos(f);
    photos.forEach((ph, j) => {
      const dy = (j - s) * H;
      const vis = Math.abs(j - s) < 1;
      show(ph.el, vis);
      if (!vis) return;
      const since = f - ARRIVE[j];
      let k = 1.0 + 0.05 * E.outCubic(P(since, 0, 60));
      let shake = 0;
      if (j === LAST) {
        const hit = f - C.land;
        k = 1.0 + 0.10 * E.outCubic(P(f, C.land, C.land + 44)) + (hit >= 0 ? 0.045 * Math.exp(-hit / 3.2) : 0);
        shake = hit >= 0 && hit < 9 ? Math.sin(hit * 2.6) * 14 * Math.exp(-hit / 2.5) : 0;
      }
      ph.el.style.transform = `translate3d(${shake * 0.6}px, ${dy + shake}px, 0)`;
      ph.img.style.transform = `scale(${k})`;
      const swing = j <= 3 || j === LAST;
      if (swing) {
        const fl = j === 0 ? f + 6 : since - 1;
        const amp = j === 0 ? -7 : j === LAST ? -22 : -16;
        const rot = amp * (1 - spring(fl, j === LAST ? 1.5 : 1.9, j === LAST ? 4.2 : 5.5));
        const op = (j === 0 ? 1 : clamp(fl / 3)) * (j === LAST ? 1 - clamp((f - (C.pull[0] - 8)) / 8) : 1);
        const drop = (1 - E.outCubic(clamp(fl / 6))) * -46;
        const sc = j === LAST ? 1.18 : 1;
        ph.tag.style.transform = `translateY(${drop}px) rotate(${rot}deg) scale(${sc})`;
        ph.tag.style.opacity = op;
      } else {
        ph.tag.style.transform = 'none'; ph.tag.style.opacity = 1;
      }
    });
  }

  const capLines = (c, inF, outF) => {
    const vis = f >= inF - 1 && f < outF + 12;
    show(c, vis);
    if (!vis) return;
    [...c.children].forEach((ln, i) => {
      const fi = f - inF - i * 2, fo = f - outF - i;
      const pin_ = inF <= 0 ? 1 : E.outBack(clamp(fi / 7), 1.6);
      const pout = E.inCubic(clamp(fo / 4));
      const y = (1 - pin_) * 70 - pout * 120;
      const sc = lerp(0.82, 1, clamp(pin_)) * (inF <= 0 ? lerp(0.97, 1, E.outCubic(clamp(f / 8))) : 1) * lerp(1, 0.9, pout);
      ln.style.transform = `translateY(${y}px) scale(${sc})`;
      ln.style.opacity = clamp(inF <= 0 ? 1 : fi / 3) * (1 - clamp(fo / 4));
    });
  };
  capLines(capA, C.capA[0], C.capA[1]);
  capLines(capB, C.capB[0], C.capB[1]);
  $('flash').style.opacity = f >= C.land ? 0.32 * (1 - clamp((f - C.land) / 6)) : 0;

  // ── reveal and shop: the phone ──────────────────────────────────────────
  const phoneOn = (f >= C.pull[0] && f < EXIT[1] + 2) || f >= C.wipe[0];
  show($('world'), phoneOn);
  show(morph, f >= C.pull[0] && f < C.pull[0] + 14);
  if (phoneOn) {
    const st = phoneState(f);
    $('phone').style.transform =
      `translate3d(${st.cx - PH.cx}px, ${st.cy - PH.cy}px, 0) rotateX(${st.rx}deg) rotateY(${st.ry}deg) rotateZ(${st.rz}deg) scale(${st.s})`;
    $('glare').style.transform = `translateX(${st.ry * 26 + Math.sin(f / 50) * 30}px)`;
    $('side').style.transform = `translate(${-st.ry * 1.25}px, ${st.rx * 1.0}px)`;
    css($('pglow'), {
      left: `${st.cx - 450}px`, top: `${st.cy - 750}px`, transform: `scale(${st.s / REST.s})`,
      opacity: f >= C.wipe[0] ? 0 : clamp((f - C.pull[0] - 7) / 14) * (1 - 0.6 * clamp((f - C.s3bg[0]) / 14)) * (1 - clamp((f - C.flood[0]) / 20)),
    });
    const { src, slot } = recSrc(f);
    if (src !== lastSrc) {
      lastSrc = src; scr.src = src;
      await scr.decode().catch(async () => {
        window.MISSING.add(src);
        scr.src = placeholder(slot, 1206, 2622);
        await scr.decode().catch(() => {});
      });
    }
    if (f < C.pull[0] + 14) {
      const s = st.s, cc = st.cardC;
      const cw = cardLocal.w * s, ch = cardLocal.h * s;
      const b = E.outCubic(clamp((f - C.pull[0]) / 5));
      css(morph, {
        left: `${lerp(0, cc.x - cw / 2, b)}px`, top: `${lerp(0, cc.y - ch / 2, b)}px`,
        width: `${lerp(W, cw, b)}px`, height: `${lerp(H, ch, b)}px`,
        opacity: 1 - clamp((f - C.pull[0] - 6) / 8), borderRadius: `${lerp(0, 22 * s, b)}px`,
      });
      morphImg.style.transform = `scale(${lerp(1.10, 1.0, clamp((f - C.pull[0]) / 6))})`;
    }
    TAPS.forEach((tp) => {
      const fr = f - tp.f;
      const on = fr > -4 && fr < 16;
      show(tp.r, on && fr >= 0); show(tp.d, on);
      if (!on) return;
      const x = tp.x * PH.sw, y = tp.y * PH.shh;
      const rr = lerp(20, 120, E.outCubic(clamp(fr / 14)));
      css(tp.r, { left: `${x - rr}px`, top: `${y - rr}px`, width: `${rr * 2}px`, height: `${rr * 2}px`, opacity: 1 - clamp(fr / 14) });
      css(tp.d, { left: `${x}px`, top: `${y}px`, opacity: clamp((fr + 4) / 3) * (1 - clamp((fr - 2) / 6)), transform: `scale(${fr < 0 ? 1.15 : lerp(0.85, 1, clamp(fr / 3))})` });
    });
  }

  // grounds
  const darkOn = f >= C.pull[0] - 1;
  show($('bg'), darkOn); show($('dots'), false); show($('glow'), darkOn); show($('pegDark'), darkOn && f < C.wipe[1]);
  // one wall, one camera: both layers share the transform, so the lit wall
  // is the same wall with the lights on
  const pegT = `perspective(1700px) rotateX(9deg) rotateY(${-15 + Math.sin(f / 70) * 4}deg) translate3d(${Math.sin(f / 55) * 30}px, ${-f * 0.55}px, -240px)`;
  $('pegDark').style.transform = pegT; $('pegLit').style.transform = pegT;
  $('glow').style.opacity = 0.8 + 0.2 * Math.sin(f / 22);
  const s3on = f >= C.s3bg[0] && f < C.flood[1] + 2;
  show($('s3bg'), s3on);
  const lw = E.inOutCubic(P(f, C.s3bg[0], C.s3bg[1]));
  show($('litEdge'), f >= C.s3bg[0] && f < C.s3bg[1] + 4);
  css($('litEdge'), { transform: `translateX(${lw * (W + 120) - 60}px) rotate(8deg)`, opacity: Math.sin(Math.PI * clamp(lw)) * 1.0 });
  if (s3on) {
    // the lights come on: a lit edge wipes across and the wall turns brand colour behind it
    css($('s3bg'), { opacity: 1, clipPath: `polygon(0 0, ${lw * 118}% 0, ${lw * 118 - 18}% 100%, 0 100%)` });
    $('s3bg').querySelector('.sweep').style.transform = `translateX(${lerp(-700, 1900, P(f, C.s3bg[1] + 8, C.s3bg[1] + 70))}px) rotate(14deg)`;
    $('s3bg').querySelector('.lamp').style.opacity = 0.75 + 0.25 * Math.sin(f / 16);
    BOKEH.forEach(({ b, x, y, r, i }) => css(b, {
      left: `${x - r / 2 + Math.sin((f + i * 40) / (38 + i * 6)) * 40}px`,
      top: `${y - r / 2 - (f - C.s3bg[0]) * (0.5 + i * 0.12)}px`,
    }));
  }

  // headlines
  const headIO = (el, inF, outF) => {
    const vis = f >= inF - 1 && f < outF + 10;
    show(el, vis);
    if (!vis) return;
    [...el.children].forEach((ln, i) => {
      const pi = E.outCubic(clamp((f - inF - i * 3) / 9));
      const po = E.inCubic(clamp((f - outF - i * 2) / 7));
      ln.style.transform = `translateY(${(1 - pi) * 60 - po * 90}px)`;
      ln.style.opacity = pi * (1 - po);
      ln.style.filter = `blur(${(1 - pi) * 10 + po * 8}px)`;
    });
  };
  headIO(head2, C.head2[0], C.head2[1]);
  headIO(head3a, C.head3a[0], C.head3a[1]);
  headIO(head3b, C.head3b[0], C.head3b[1]);

  // reveal: category cards
  CATS.forEach((c, i) => {
    const fi = f - C.cats[0] - i * 5, fo = f - C.cats[1] - i * 2;
    const vis = fi > -1 && fo < 12;
    show(c.el, vis);
    if (!vis) return;
    const sp = spring(fi, 1.8, 6.5);
    const out = E.inCubic(clamp(fo / 10));
    const ox = 540 - 115, oy = 1150 - 140;                       // launched from the phone
    const away = (c.x < 540 ? -1 : 1) * 240 * out;
    const x = lerp(ox, c.x, clamp(sp)) + (sp - clamp(sp)) * (c.x - ox) * 0.4 + away;
    const y = lerp(oy, c.y, clamp(sp)) + Math.sin((f + i * 13) / 18) * 7 - out * 60;
    css(c.el, {
      left: `${x}px`, top: `${y}px`, opacity: clamp(fi / 4) * (1 - out),
      transform: `rotate(${c.rot * clamp(sp) + Math.sin((f + i * 7) / 24) * 1.2}deg) scale(${lerp(0.35, 1, sp) * lerp(1, 0.85, out)})`,
    });
  });

  // shop: the tags on the wall, the bubble, the flying item
  const chipsOut = E.inCubic(P(f, C.chipsOut, C.chipsOut + 10));
  const hangChip = (h, inF, px, py, side) => {
    const fi = f - inF;
    const vis = fi > -1 && f < C.chipsOut + 12;
    show(h.w, vis); show(h.pin, vis);
    if (!vis) return;
    const drop = spring(fi, 1.9, 6.0);
    const swing = side * 16 * Math.exp(-fi / 14) * Math.cos(fi / 3.2) * clamp(fi / 2) + Math.sin((f + inF) / 26) * 1.4;
    const cw = h.c.offsetWidth;
    h.c.style.left = `${-cw / 2}px`;
    px = clamp(px, 24 + cw / 2, W - 24 - cw / 2);       // a long tag moves its pin inward rather than leave the frame
    css(h.w, { left: `${px}px`, top: `${py}px`, transform: `translateY(${(1 - drop) * -170 + chipsOut * 50}px) rotate(${swing}deg)`, opacity: clamp(fi / 3) * (1 - chipsOut) });
    css(h.pin, { left: `${px}px`, top: `${py}px`, opacity: clamp(fi / 3) * (1 - chipsOut) });
  };
  hangs.forEach(({ h, cue, x, y, side }) => hangChip(h, C[cue], x, y, side));
  const cb = { x: 952, y: 610 };
  {
    const fi = f - C.cart;
    const vis = fi > -1 && f < C.chipsOut + 12;
    show(cartb, vis);
    if (vis) {
      const { s, o } = popIn(fi, 0.4);
      const bump = f >= C.badge ? 1 + 0.16 * Math.exp(-(f - C.badge) / 4) * Math.cos((f - C.badge) * 0.9) : 1;
      css(cartb, { left: `${cb.x - 75}px`, top: `${cb.y - 75 + Math.sin(f / 20) * 5}px`, opacity: o * (1 - chipsOut), transform: `scale(${s * bump * lerp(1, 0.9, chipsOut)})` });
      const bs = f >= C.badge ? spring(f - C.badge, 2.4, 7) : 0;
      css($('badge'), { transform: `scale(${bs})`, opacity: f >= C.badge ? 1 : 0 });
    }
  }
  {
    const p = P(f, C.fly[0], C.fly[1]);
    const vis = f >= C.fly[0] && f < C.fly[1];
    show(flyer, vis);
    if (vis) {
      const e = E.inOutCubic(p);
      const a = { x: 540, y: 735 }, c = { x: 820, y: 330 }, b = cb;   // quadratic arc
      const x = (1 - e) ** 2 * a.x + 2 * (1 - e) * e * c.x + e * e * b.x;
      const y = (1 - e) ** 2 * a.y + 2 * (1 - e) * e * c.y + e * e * b.y;
      css(flyer, { left: `${x - 85}px`, top: `${y - 85}px`, transform: `scale(${lerp(1, 0.28, e)}) rotate(${e * 24}deg)`, opacity: clamp(f - C.fly[0]) * (1 - clamp((p - 0.85) / 0.15)) });
    }
  }
  ghosts.forEach((g, k) => {
    const lag = (k + 1) * 1.6, fg = f - lag;
    const p = P(fg, C.fly[0], C.fly[1]);
    const vis = fg >= C.fly[0] && fg < C.fly[1] && f < C.fly[1] + 2;
    show(g, vis);
    if (!vis) return;
    const e = E.inOutCubic(p);
    const a = { x: 540, y: 735 }, c = { x: 820, y: 330 }, b = cb;
    const x = (1 - e) ** 2 * a.x + 2 * (1 - e) * e * c.x + e * e * b.x;
    const y = (1 - e) ** 2 * a.y + 2 * (1 - e) * e * c.y + e * e * b.y;
    css(g, { left: `${x - 85}px`, top: `${y - 85}px`, transform: `scale(${lerp(1, 0.28, e) * (1 - k * 0.07)}) rotate(${e * 24}deg)`,
             opacity: 0.32 * (1 - k / 5) * (1 - clamp((p - 0.8) / 0.2)), filter: `blur(${3 + k * 2}px) ${K.trailFilter}` });
  });
  sparks.forEach((sp, i) => {
    const fr = f - C.badge;
    const vis = fr >= 0 && fr < 18;
    show(sp, vis);
    if (!vis) return;
    const ang = (i / sparks.length) * Math.PI * 2 + 0.3;
    const d = lerp(40, 150 + (i % 3) * 25, E.outCubic(fr / 18));
    css(sp, { left: `${cb.x + Math.cos(ang) * d}px`, top: `${cb.y + Math.sin(ang) * d}px`, opacity: 1 - fr / 18, transform: `scale(${lerp(1.3, 0.3, fr / 18)})` });
  });

  // ── value: the big line on the flood ────────────────────────────────────
  const flood = $('flood');
  const fr = E.inOutCubic(P(f, C.flood[0], C.flood[1]));
  const floodOut = PLACE ? E.inOutCubic(P(f, C.card[0] - 2, C.card[0] + 14)) : 0;
  show(flood, f >= C.flood[0] && f < (PLACE ? C.card[0] + 16 : C.wipe[1] + 2));
  if (f >= C.flood[0]) css(flood, { opacity: 1 - floodOut, clipPath: `circle(${fr * 2300}px at 540px 560px)` });
  const payOn = f >= C.pay[0] - 4 && f < VALUE_OUT + 14;
  show(pay, payOn);
  if (payOn) {
    [...pay.querySelectorAll('.word')].forEach((w, i) => {
      const at = C.pay[i] ?? C.pay[C.pay.length - 1] + 5 * (i - C.pay.length + 1);
      const fi = f - at;
      const sp = spring(fi, 2.0, 9);
      const out = E.inCubic(P(f, VALUE_OUT + i, VALUE_OUT + 10 + i));
      w.style.transform = `translateY(${(1 - clamp(sp)) * 90 - out * 140}px) scale(${lerp(0.55, 1, sp)}) rotate(${(1 - clamp(sp)) * -6}deg)`;
      w.style.opacity = clamp(fi / 2) * (1 - out);
    });
  }
  const chipOn = f >= C.payChip - 4 && f < VALUE_OUT + 14;
  show(chip, chipOn);
  if (chipOn) {
    const sp = spring(f - C.payChip, 2.2, 7);
    const out = E.inCubic(P(f, VALUE_OUT, VALUE_OUT + 10));
    css(chip, { left: `${540 - chip.offsetWidth / 2}px`, top: '905px', transform: `translateY(${(1 - clamp(sp)) * 60 - out * 120}px) scale(${lerp(0.7, 1, sp)})`, opacity: clamp((f - C.payChip + 2) / 3) * (1 - out) });
  }

  // ── place: the photo card, the headline, the location (optional) ────────
  const cardOn = PLACE && f >= C.card[0] - 2 && f < C.card[3];
  show($('cardWrap'), !!cardOn);
  if (cardOn) {
    const pi = E.outQuint(P(f, C.card[0], C.card[1]));
    const po = E.inOutCubic(P(f, C.card[2], C.card[3]));
    $('card').style.transform = `perspective(2200px) translateY(${(1 - pi) * 900 - po * 80}px) rotateX(${(1 - pi) * 24}deg) rotateY(${lerp(-5, 3, P(f, C.card[0], C.card[2]))}deg) scale(${lerp(1, 0.9, po)})`;
    $('card').style.opacity = 1 - po;
    $('card').querySelector('img').style.transform = `scale(${lerp(1.06, 1.14, P(f, C.card[0], C.card[2]))})`;
  }
  if (PLACE) headIO(pick, C.pick[0], C.pick[1]); else show(pick, false);
  const locOn = PLACE && f >= C.loc[0] - 2 && f < C.loc[1] + 12;
  show(loc, !!locOn); show(pin, !!locOn);
  if (locOn) {
    const sp = spring(f - (C.loc[0] + 2), 2.1, 6.5);
    const po = E.inCubic(P(f, C.loc[1], C.loc[1] + 10));
    css(loc, { left: '170px', top: '1440px', transform: `translateY(${(1 - clamp(sp)) * 70 - po * 60}px) scale(${lerp(0.85, 1, sp)})`, opacity: clamp((f - C.loc[0]) / 3) * (1 - po) });
    const drop = spring(f - C.pin, 2.6, 5.2);
    css(pin, { left: '196px', top: '1452px', transform: `translateY(${(1 - drop) * -260 - po * 60}px)`, opacity: clamp((f - C.pin + 1) / 2) * (1 - po) });
  }

  // ── end card ────────────────────────────────────────────────────────────
  const endOn = f >= C.wipe[0];
  show($('white'), endOn); show(end, endOn); show($('pegEnd'), endOn);
  if (endOn) $('pegEnd').style.transform = `perspective(1700px) rotateX(9deg) rotateY(${-15 + Math.sin(f / 70) * 4}deg) translate3d(${Math.sin(f / 55) * 30}px, ${-f * 0.55}px, -240px)`;
  if (endOn) {
    const w = E.inOutCubic(P(f, C.wipe[0], C.wipe[1]));
    css($('white'), { opacity: 1, clipPath: `circle(${w * 2300}px at 540px 960px)` });
    const lg = spring(f - C.logo, 1.8, 6);
    css($('logo'), { transform: `scale(${lerp(0.82, 1, lg)})`, opacity: clamp((f - C.logo) / 4) });
    const hd = E.outCubic(P(f, C.endHead, C.endHead + 12));
    css($('endHead'), { transform: `translateY(${(1 - hd) * 60}px)`, opacity: hd });
    const gap = 14, ws = ECHIPS.map((e) => e.offsetWidth), tot = ws.reduce((a, b) => a + b, 0) + gap * (ECHIPS.length - 1);
    let x = (W - tot) / 2;
    ECHIPS.forEach((e, i) => {
      const { s, o } = popIn(f - C.endChips - i * 4, 0.6);
      css(e, { left: `${x}px`, top: '795px', transform: `scale(${s})`, opacity: o });
      x += ws[i] + gap;
    });
    const ba = spring(f - C.badges[0], 2.0, 6.5), bg = spring(f - C.badges[1], 2.0, 6.5);
    const bA = $('bA'), bG = $('bG');
    const bh = 132, wA = bh * bA.naturalWidth / bA.naturalHeight, wG = bh * bG.naturalWidth / bG.naturalHeight, x0 = (W - wA - wG - 22) / 2;
    css(bA, { height: `${bh}px`, left: `${x0}px`, top: '900px', transform: `scale(${lerp(0.6, 1, ba)})`, opacity: clamp((f - C.badges[0]) / 3) });
    css(bG, { height: `${bh}px`, left: `${x0 + wA + 22}px`, top: '900px', transform: `scale(${lerp(0.6, 1, bg)})`, opacity: clamp((f - C.badges[1]) / 3) });
  }
  $('vig').style.opacity = endOn ? 0 : f < C.pull[0] ? 0.55 : 1;

  if (window.DEBUG_SAFE) drawSafe();
  return true;
};

function drawSafe() {
  const c = $('safe').getContext('2d');
  c.clearRect(0, 0, W, H);
  c.fillStyle = 'rgba(255,0,80,.22)';
  c.fillRect(0, 0, W, 200); c.fillRect(0, 1590, W, 330); c.fillRect(950, 1060, 130, 530);
}
