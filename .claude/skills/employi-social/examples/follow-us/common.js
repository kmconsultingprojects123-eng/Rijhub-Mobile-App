'use strict';
// Shared pieces for HTML posts. Every page builds into #poster (1080x1350),
// registers its information elements with box(), and exposes
// window.ready(qrSvg) for shoot.mjs, which checks overlaps and margins.
// starter.html is the smallest page that uses all of it.
const W = 1080, H = 1350;
const P = document.getElementById('poster');

// TODO, the same TODO as scripts/brand.py: Employi has no confirmed website.
// Keep these null until the user names the domain; site() and qr() refuse
// while they are, so no page prints a guessed URL or draws a QR to one.
const SITE = null;      // the domain people type, e.g. '<domain>'
const APP_URL = null;   // the QR's link, e.g. 'https://<domain>/app'

// TODO: Employi's social handles are not on record (the app and the
// backend name none). Fill this from the user, in the form
//   { k: 'instagram', name: 'Instagram', h: '@handle' }
// with k one of the icons in assets/icons.js: instagram, tiktok, x, facebook.
const HANDLES = [];

function need(value, what) {
  if (value == null || (Array.isArray(value) && !value.length)) {
    throw new Error(`refusing to render: ${what} is a TODO in common.js (and scripts/brand.py); ask the user, never guess`);
  }
  return value;
}
function site() { return need(SITE, 'SITE'); }

// The skill's own assets, shared with build.py: no copies in this folder.
const ASSET = '../../assets';
// Captures live outside the skill; shoot.mjs passes their folder in
// (default ~/Downloads/employi-screens, or SCREENS=...).
function screen(name) { return `file://${window.SCREENS}/${name}`; }

function el(cls, html, parent = P, tag = 'div') { const d = document.createElement(tag); if (cls) d.className = cls; if (html != null) d.innerHTML = html; parent.appendChild(d); return d; }
function css(n, o) { Object.assign(n.style, o); return n; }
function at(n, x, y, extra = {}) { return css(n, { left: `${x}px`, top: `${y}px`, ...extra }); }
function icon(name, size, color) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" style="display:block;flex:none;fill:${color}"><path d="${window.ICONS[name]}"/></svg>`;
}
// The Employi logo: the app's own file, scaled by height. Never redrawn or
// recoloured. variant: 'color' (light grounds), 'onDark', 'white' (crimson grounds).
function logo(h, variant = 'color', parent = P) {
  const file = { color: 'logo.png', onDark: 'logo-on-dark.png', white: 'logo-white.png' }[variant];
  return el('logo', `<img src="${ASSET}/brand/${file}" style="height:${h}px">`, parent);
}
// A phone; src is a path as given, or a file in this folder's assets/.
function phone(src, parent = P) {
  const url = src.includes('/') ? src : `assets/${src}`;
  return el('phone', '<div class="pbody"></div><div class="pbtn l1"></div><div class="pbtn l2"></div><div class="pbtn l3"></div><div class="pbtn r1"></div>'
    + `<div class="pscreen"><img src="${url}"></div><div class="pisland"></div><div class="pglare"></div>`, parent);
}
// centre (cx, cy), width w (the body), rotation r degrees
function placePhone(ph, cx, cy, w, r) { ph.style.transform = `translate(${cx}px,${cy}px) rotate(${r}deg) scale(${w / 640}) translate(-320px,-677px)`; }
function qr(size, bg, radius, parent = P) {
  need(APP_URL, 'APP_URL');
  const n = el('qr', null, parent); n.style.cssText += `;position:absolute;width:${size}px;height:${size}px;background:${bg};border-radius:${radius}px`;
  n.dataset.size = size; return n;
}
function fillQR(n) {
  if (!window.QRSVG) throw new Error('a QR is placed but shoot.mjs was given no QR svg (name:S reads assets/qrS.svg)');
  const size = Number(n.dataset.size), pad = Math.round(size * 0.09), inner = size - 2 * pad;
  const m = Number(/width="(\d+)"/.exec(window.QRSVG)[1]);
  n.innerHTML = window.QRSVG.replace(/<svg /, `<svg style="left:${pad}px;top:${pad}px;width:${inner}px;height:${inner}px" viewBox="0 0 ${m} ${m}" preserveAspectRatio="none" `)
    .replace(/ width="\d+" height="\d+"/, '');
}
// Official store badges: plain ones are stroke-stripped for light grounds,
// -dark ones keep the outline for dark grounds (SKILL.md, traps).
function badges(dark, h, gap, vertical = false, parent = P) {
  const s = dark ? '-dark' : '';
  const n = el('badges', `<img src="${ASSET}/badges/app-store${s}.png" style="height:${h}px"><img src="${ASSET}/badges/google-play${s}.png" style="height:${h}px">`, parent);
  css(n, { gap: `${gap}px`, flexDirection: vertical ? 'column' : 'row', alignItems: vertical ? 'flex-start' : 'center' });
  return n;
}
// seeded randomness, so a page renders the same every time
let seed = 11;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
// Information elements are checked for overlaps within their group: 'poster'
// (measured on the page) or a rotated container such as a card (measured in
// the container's own, unrotated coordinates). Objects placed with a rotation
// register an oriented box with obox(); shoot.mjs checks those with SAT.
const BOX = {}, OBOX = {};
function box(name, n, group = null) { BOX[name] = { n, group }; return n; }
function obox(name, cx, cy, w, h, r, opts = {}) { OBOX[name] = { cx, cy, w, h, r, ...opts }; }
function localRect(n, group) {
  let x = 0, y = 0, e = n;
  while (e && e !== group) { x += e.offsetLeft; y += e.offsetTop; e = e.offsetParent; }
  if (e !== group) throw new Error('box is not inside its group');
  return [x, y, x + n.offsetWidth, y + n.offsetHeight];
}
function fit(n, maxW) { const w = n.getBoundingClientRect().width; if (w > maxW) n.style.fontSize = `${parseFloat(getComputedStyle(n).fontSize) * maxW / w}px`; }
window.ready = async (qrsvg) => {
  window.QRSVG = qrsvg;
  for (const w of [400, 500, 600, 700, 800]) await document.fonts.load(`${w} 40px P`);

  await document.fonts.ready;
  document.querySelectorAll('.qr').forEach(fillQR);
  await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
  if (window.layout) await window.layout();
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  const groups = {};
  for (const [k, { n, group }] of Object.entries(BOX)) {
    const g = group ? group.dataset.group : 'poster';
    let r;
    if (group) r = localRect(n, group);
    else { const b = n.getBoundingClientRect(); r = [b.left, b.top, b.right, b.bottom]; }
    (groups[g] = groups[g] || {})[k] = r.map((v) => Math.round(v));
  }
  return { groups, obox: OBOX };
};
