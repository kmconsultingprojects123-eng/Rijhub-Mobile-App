'use strict';
// Knolling layout: the kit laid out round the device in regions (a column
// either side, a row along the bottom, a spot beside a short headline line),
// every tool square to the canvas and spaced evenly, as a tradesman lays
// out a kit. Tools keep their sizes relative to each other (one scale, k,
// per format) and only shrink when a region can't hold them.

function dims(svgText) {
  const w = +/width="([\d.]+)"/.exec(svgText)[1], h = +/height="([\d.]+)"/.exec(svgText)[1];
  return [w, h];
}

/** Draws TOOLS[name] in the box (x, y, w, h); `turn` lays it on its side. */
function drawTool(name, x, y, w, h, turn = 0, label = name) {
  const text = TOOLS[name]();
  const n = el('tool', text);
  const svg = n.querySelector('svg');
  const [sw, sh] = turn ? [h, w] : [w, h];
  svg.setAttribute('width', sw); svg.setAttribute('height', sh);
  css(n, { position: 'absolute', left: `${x}px`, top: `${y}px`, width: `${w}px`, height: `${h}px` });
  css(svg, { position: 'absolute', left: '50%', top: '50%', display: 'block',
    transform: `translate(-50%, -50%)${turn ? ` rotate(${turn * 90}deg)` : ''}` });
  obox(label, x + w / 2, y + h / 2, w, h, 0);
  return n;
}

/**
 * Packs `items` into `region` ({x, y, w, h}) along `dir` ('col' or 'row'),
 * spaced evenly. Each item: {t: tool, s: extra scale, turn: ±1, n: repeats}.
 * Returns nothing; draws the tools.
 */
function pack(region, items, dir, k, tag) {
  if (!items || !items.length || region.w <= 0 || region.h <= 0) return;
  const col = dir === 'col';
  const boxes = items.map((it) => {
    let [w, h] = dims(TOOLS[it.t]());
    if (it.turn) [w, h] = [h, w];
    const s = k * (it.s || 1);
    return { it, w: w * s, h: h * s, n: it.n || 1 };
  });
  const cross = col ? region.w : region.h, main = col ? region.h : region.w;
  const repGap = 0.35;                       // repeats sit closer than items
  const len = (b) => (col ? b.h : b.w) * (b.n + repGap * (b.n - 1));
  // Too wide for the region: that item shrinks to fit.
  for (const b of boxes) {
    const c = col ? b.w : b.h;
    if (c > cross) { const f = cross / c; b.w *= f; b.h *= f; }
  }
  // Too long altogether: everything shrinks together.
  const minGap = 0.05 * main;
  let total = boxes.reduce((t, b) => t + len(b), 0);
  if (total + minGap * (boxes.length + 1) > main) {
    const f = (main - minGap * (boxes.length + 1)) / total;
    for (const b of boxes) { b.w *= f; b.h *= f; }
    total = boxes.reduce((t, b) => t + len(b), 0);
  }
  const gap = (main - total) / (boxes.length + 1);
  let at = (col ? region.y : region.x) + gap;
  boxes.forEach((b, i) => {
    for (let r = 0; r < b.n; r++) {
      const step = (col ? b.h : b.w) * (1 + repGap);
      const x = col ? region.x + (region.w - b.w) / 2 : at + r * step;
      const y = col ? at + r * step : region.y + (region.h - b.h) / 2;
      drawTool(b.it.t, x, y, b.w, b.h, b.it.turn || 0, `${tag}-${i}-${r}`);
    }
    at += len(b) + gap;
  });
}
