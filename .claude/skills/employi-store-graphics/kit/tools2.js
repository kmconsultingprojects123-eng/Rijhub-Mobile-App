'use strict';
// More of the kit, one set per graphic: checking (an ID card, a magnifier,
// a stamp and its mark, a price tag, a multimeter), paying (a padlock and
// key, a tear-off calendar, a stopwatch, a card, a receipt), the site (a hard
// hat, gloves, a torch, a clipboard with the job's steps), talking (two
// walkie-talkies, crimson and black like the logo's halves, a notepad) and
// getting paid (a toolbox, a wallet, pliers). Same rules as tools.js: drawn
// flat from above, long axis vertical, brand palette only.
Object.assign(TOOLS, (() => {
  let uid = 0;
  const id = (p) => `t2${p}${++uid}`;
  const lin = (g, stops, v = false) => `<linearGradient id="${g}" x1="0" y1="0" x2="${v ? 0 : 1}" y2="${v ? 1 : 0}">${stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('')}</linearGradient>`;
  const rad = (g, stops, cx = '.38', cy = '.34', r = '.75') => `<radialGradient id="${g}" cx="${cx}" cy="${cy}" r="${r}">${stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join('')}</radialGradient>`;
  const STEEL = [[0, '#9AA1A8'], [0.18, '#E9ECEF'], [0.42, '#C3C9CF'], [0.7, '#F3F5F7'], [1, '#8E959C']];
  const CRIMSON = [[0, '#6F0019'], [0.25, '#C4002F'], [0.45, '#D21540'], [0.75, '#A20025'], [1, '#5E0015']];
  const RUBBER = [[0, '#0B0B0B'], [0.35, '#3A3A3A'], [0.6, '#202020'], [1, '#070707']];
  const PAPER = [[0, '#FFFFFF'], [1, '#F1EEE8']];
  const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;
  const T = (x, y, size, weight, fill, text, extra = '') => `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" ${extra}>${text}</text>`;

  // ── checking ─────────────────────────────────────────────────────────────
  function idCard() {
    const p = id('p'), c = id('c'), k = id('k');
    return svg(520, 330, `<defs>${lin(p, PAPER, true)}${lin(c, CRIMSON)}<clipPath id="${k}"><rect x="34" y="104" width="136" height="170" rx="14"/></clipPath></defs>
      <rect x="1" y="1" width="518" height="328" rx="28" fill="url(#${p})" stroke="rgba(0,0,0,.08)" stroke-width="2"/>
      <path d="M1 29 A28 28 0 0 1 29 1 H491 A28 28 0 0 1 519 29 V80 H1 Z" fill="url(#${c})"/>
      ${T(34, 52, 25, 800, '#FFF', 'ARTISAN ID', 'letter-spacing="4"')}
      <g clip-path="url(#${k})"><rect x="34" y="104" width="136" height="170" fill="#E9E6E1"/>
        <circle cx="102" cy="166" r="34" fill="#C7C1B8"/><path d="M46 280 C46 230 72 212 102 212 C132 212 158 230 158 280 Z" fill="#C7C1B8"/></g>
      <rect x="200" y="112" width="200" height="24" rx="12" fill="#262626"/>
      <rect x="200" y="156" width="250" height="14" rx="7" fill="#D3CEC6"/><rect x="200" y="184" width="180" height="14" rx="7" fill="#D3CEC6"/>
      <rect x="200" y="212" width="220" height="14" rx="7" fill="#D3CEC6"/>
      <circle cx="452" cy="262" r="40" fill="#16A34A"/><path d="M434 262 L447 275 L471 249" stroke="#FFF" stroke-width="9" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`);
  }

  function magnifier() {
    const s = id('s'), g = id('g'), r = id('r'), c = id('c');
    return svg(250, 600, `<defs>${lin(s, STEEL)}${rad(g, [[0, 'rgba(255,255,255,.95)'], [0.55, 'rgba(236,244,247,.85)'], [1, 'rgba(196,220,228,.9)']])}${lin(r, RUBBER)}${lin(c, CRIMSON)}</defs>
      <circle cx="125" cy="125" r="118" fill="url(#${s})"/><circle cx="125" cy="125" r="94" fill="url(#${g})"/>
      <circle cx="125" cy="125" r="94" fill="none" stroke="rgba(0,0,0,.12)" stroke-width="3"/>
      <path d="M66 96 A66 66 0 0 1 120 60" stroke="#FFF" stroke-width="11" fill="none" stroke-linecap="round" opacity=".9"/>
      <rect x="108" y="238" width="34" height="52" fill="url(#${s})"/><rect x="99" y="286" width="52" height="34" rx="8" fill="url(#${c})"/>
      <rect x="96" y="316" width="58" height="280" rx="28" fill="url(#${r})"/><circle cx="125" cy="560" r="10" fill="#EAE5DE"/>`);
  }

  function stamp() {
    const c = id('c'), r = id('r');
    return svg(200, 320, `<defs>${lin(c, CRIMSON)}${lin(r, RUBBER)}</defs>
      <ellipse cx="100" cy="62" rx="62" ry="58" fill="url(#${c})"/>
      <path d="M58 30 A52 52 0 0 1 100 12" stroke="rgba(255,255,255,.4)" stroke-width="9" fill="none" stroke-linecap="round"/>
      <path d="M70 110 H130 L124 218 H76 Z" fill="url(#${c})"/>
      <rect x="10" y="214" width="180" height="66" rx="12" fill="url(#${r})"/>
      <rect x="18" y="280" width="164" height="28" rx="5" fill="#6C0019"/>`);
  }

  function stampMark() {
    const p = id('p'), f = id('f');
    return svg(420, 250, `<defs>${lin(p, PAPER, true)}
        <filter id="${f}" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="1.6" numOctaves="2" seed="4"/>
          <feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -2.2 1.6"/><feComposite in="SourceGraphic" operator="in"/></filter></defs>
      <rect x="1" y="1" width="418" height="248" rx="10" fill="url(#${p})" stroke="rgba(0,0,0,.07)" stroke-width="2"/>
      <g filter="url(#${f})" transform="rotate(-7 210 125)" opacity=".93">
        <rect x="52" y="52" width="316" height="146" rx="24" fill="none" stroke="#A20025" stroke-width="10"/>
        ${T(210, 124, 52, 900, '#A20025', 'CHECKED', 'text-anchor="middle" letter-spacing="3"')}
        <path d="M178 146 L198 166 L244 120" stroke="#A20025" stroke-width="13" fill="none" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 6)"/>
      </g>`);
  }

  function priceTag() {
    const p = id('p');
    return svg(400, 170, `<defs>${lin(p, PAPER, true)}</defs>
      <path d="M126 85 C96 64 60 50 4 46" stroke="#A20025" stroke-width="5" fill="none" stroke-linecap="round"/>
      <path d="M150 1 H379 A20 20 0 0 1 399 21 V149 A20 20 0 0 1 379 169 H150 L92 85 Z" fill="url(#${p})" stroke="rgba(0,0,0,.09)" stroke-width="2"/>
      <circle cx="130" cy="85" r="13" fill="#EAE5DE" stroke="#B9BEC4" stroke-width="5"/>
      ${T(268, 104, 50, 800, '#171717', '₦10,000', 'text-anchor="middle" letter-spacing="-1"')}`);
  }

  function pencil() {
    const c = id('c');
    return svg(64, 520, `<defs>${lin(c, CRIMSON)}</defs>
      <rect x="6" y="0" width="52" height="424" rx="4" fill="url(#${c})"/>
      <rect x="6" y="0" width="52" height="28" rx="4" fill="#171717"/>
      <path d="M20 34 V412" stroke="rgba(255,255,255,.28)" stroke-width="5" stroke-linecap="round"/>
      <path d="M6 422 H58 L44 488 H20 Z" fill="#E6C49B"/><path d="M20 486 H44 L36 520 H28 Z" fill="#2A2A2A"/>`);
  }

  function clip() {
    const s = id('s');
    return svg(70, 230, `<defs>${lin(s, STEEL)}</defs>
      <path d="M22 66 V176 A13 13 0 0 0 48 176 V34 A21 21 0 0 0 6 34 V186 A29 29 0 0 0 64 186 V56" stroke="url(#${s})" stroke-width="7" fill="none" stroke-linecap="round"/>`);
  }

  function multimeter() {
    const c = id('c'), r = id('r'), s = id('s');
    let marks = '';
    for (let i = 0; i < 9; i++) {
      const a = (-150 + i * 37.5) * Math.PI / 180;
      marks += `<path d="M${150 + Math.sin(a) * 88} ${300 - Math.cos(a) * 88} L${150 + Math.sin(a) * 100} ${300 - Math.cos(a) * 100}" stroke="#E6E6E6" stroke-width="5" stroke-linecap="round"/>`;
    }
    return svg(300, 520, `<defs>${lin(c, CRIMSON)}${lin(r, RUBBER)}${rad(s, STEEL.map(([o, k]) => [o, k]), '.4', '.35', '.8')}</defs>
      <rect x="0" y="0" width="300" height="520" rx="48" fill="url(#${c})"/>
      <rect x="22" y="22" width="256" height="476" rx="32" fill="url(#${r})"/>
      <rect x="50" y="56" width="200" height="118" rx="12" fill="#C6D2C9"/>
      ${T(222, 146, 74, 600, '#26302A', '230', 'text-anchor="end" letter-spacing="-2"')}${T(228, 146, 30, 700, '#26302A', 'V')}
      ${marks}<circle cx="150" cy="300" r="74" fill="url(#${s})"/><circle cx="150" cy="300" r="54" fill="#1C1C1C"/>
      <rect x="143" y="242" width="14" height="56" rx="7" fill="#F2F2F2"/>
      <circle cx="84" cy="438" r="20" fill="#0B0B0B" stroke="#555" stroke-width="5"/><circle cx="150" cy="438" r="20" fill="#0B0B0B" stroke="#555" stroke-width="5"/>
      <circle cx="216" cy="438" r="20" fill="#0B0B0B" stroke="#C4002F" stroke-width="6"/>`);
  }

  // ── paying ───────────────────────────────────────────────────────────────
  function padlock() {
    const s = id('s'), c = id('c');
    return svg(260, 360, `<defs>${lin(s, STEEL)}${lin(c, CRIMSON)}</defs>
      <path d="M62 176 V104 A68 68 0 0 1 198 104 V176" stroke="url(#${s})" stroke-width="30" fill="none"/>
      <rect x="0" y="150" width="260" height="210" rx="36" fill="url(#${c})"/>
      <rect x="14" y="160" width="232" height="18" rx="9" fill="rgba(255,255,255,.18)"/>
      <circle cx="130" cy="244" r="22" fill="#1C1C1C"/><path d="M121 252 H139 L135 300 H125 Z" fill="#1C1C1C"/>`);
  }

  function key() {
    const s = id('s'), c = id('c');
    return svg(110, 420, `<defs>${lin(s, STEEL)}${lin(c, CRIMSON)}</defs>
      <path d="M10 58 A45 45 0 0 1 100 58 V112 A20 20 0 0 1 80 132 H30 A20 20 0 0 1 10 112 Z" fill="url(#${c})"/>
      <circle cx="55" cy="54" r="15" fill="#EAE5DE"/>
      <path d="M38 130 H72 V220 H62 V240 H72 V268 H58 V284 H72 V318 H64 V342 H72 V380 L56 414 L38 398 Z" fill="url(#${s})"/>
      <path d="M48 140 V390" stroke="rgba(0,0,0,.14)" stroke-width="4"/>`);
  }

  function calendar() {
    const p = id('p'), c = id('c'), s = id('s');
    return svg(300, 340, `<defs>${lin(p, PAPER, true)}${lin(c, CRIMSON)}${lin(s, STEEL)}</defs>
      <rect x="1" y="22" width="298" height="316" rx="24" fill="url(#${p})" stroke="rgba(0,0,0,.08)" stroke-width="2"/>
      <path d="M1 46 A24 24 0 0 1 25 22 H275 A24 24 0 0 1 299 46 V112 H1 Z" fill="url(#${c})"/>
      ${T(150, 86, 36, 800, '#FFF', 'OCT', 'text-anchor="middle" letter-spacing="6"')}
      ${T(150, 252, 150, 800, '#171717', '24', 'text-anchor="middle" letter-spacing="-6"')}
      ${T(150, 306, 26, 700, '#6B6B6B', 'SATURDAY', 'text-anchor="middle" letter-spacing="5"')}
      <rect x="72" y="0" width="22" height="50" rx="11" fill="url(#${s})"/><rect x="206" y="0" width="22" height="50" rx="11" fill="url(#${s})"/>`);
  }

  function stopwatch() {
    const s = id('s'), r = id('r');
    let ticks = '';
    for (let i = 0; i < 60; i++) {
      const a = i * 6 * Math.PI / 180, long = i % 5 === 0;
      const r0 = long ? 92 : 102;
      ticks += `<path d="M${150 + Math.sin(a) * r0} ${222 - Math.cos(a) * r0} L${150 + Math.sin(a) * 110} ${222 - Math.cos(a) * 110}" stroke="#262626" stroke-width="${long ? 5 : 2.5}" stroke-linecap="round"/>`;
    }
    const a = 120 * Math.PI / 180;
    return svg(300, 370, `<defs>${lin(s, STEEL)}${lin(r, RUBBER)}</defs>
      <rect x="126" y="0" width="48" height="34" rx="9" fill="url(#${s})"/><rect x="138" y="30" width="24" height="26" fill="url(#${s})"/>
      <circle cx="150" cy="222" r="146" fill="url(#${r})"/><circle cx="150" cy="222" r="124" fill="#FAFAFA"/>
      ${ticks}
      ${T(150, 176, 26, 700, '#262626', '60', 'text-anchor="middle"')}
      <path d="M150 222 L${150 + Math.sin(a) * 96} ${222 - Math.cos(a) * 96}" stroke="#A20025" stroke-width="7" stroke-linecap="round"/>
      <circle cx="150" cy="222" r="12" fill="#A20025"/>`);
  }

  function card() {
    const g = id('g'), s = id('s'), c = id('c');
    return svg(430, 270, `<defs>${lin(g, [[0, '#2E2E2E'], [1, '#0E0E0E']])}${lin(s, STEEL)}${lin(c, CRIMSON)}</defs>
      <rect x="0" y="0" width="430" height="270" rx="26" fill="url(#${g})"/>
      <path d="M300 0 H404 A26 26 0 0 1 430 26 V244 A26 26 0 0 1 404 270 H232 Z" fill="url(#${c})" opacity=".92"/>
      <rect x="40" y="86" width="72" height="56" rx="10" fill="url(#${s})"/>
      <path d="M40 104 H112 M40 124 H112 M76 86 V142" stroke="rgba(0,0,0,.25)" stroke-width="3"/>
      <path d="M140 96 A30 30 0 0 1 140 132 M152 88 A42 42 0 0 1 152 140 M164 80 A54 54 0 0 1 164 148" stroke="#D9D9D9" stroke-width="5" fill="none" stroke-linecap="round"/>
      ${T(40, 222, 27, 600, 'rgba(255,255,255,.78)', '••••  ••••  ••••  4829', 'letter-spacing="2"')}`);
  }

  function coin() {
    const s = id('s');
    return svg(120, 120, `<defs>${rad(s, [[0, '#F4F6F8'], [0.6, '#C5CBD1'], [1, '#8E959C']])}</defs>
      <circle cx="60" cy="60" r="57" fill="url(#${s})" stroke="rgba(0,0,0,.12)" stroke-width="2"/>
      <circle cx="60" cy="60" r="44" fill="none" stroke="rgba(0,0,0,.14)" stroke-width="3"/>
      <circle cx="60" cy="60" r="44" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2" transform="translate(-1.5 -1.5)"/>`);
  }

  function receipt() {
    const p = id('p'), W = 280, R = W - 28;
    let zig = '';
    for (let x = W; x > 0; x -= 20) zig += ` L${x - 10} 504 L${x - 20} 520`;
    const bar = (x, y, w, c = '#D3CEC6', h = 12) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${h / 2}" fill="${c}"/>`;
    return svg(W, 520, `<defs>${lin(p, PAPER, true)}</defs>
      <path d="M0 0 H${W} V520${zig} Z" fill="url(#${p})" stroke="rgba(0,0,0,.07)" stroke-width="2"/>
      ${bar(28, 40, 130, '#262626', 16)}${bar(28, 78, 190)}${bar(28, 104, 150)}
      <path d="M28 146 H${R}" stroke="#CFCAC2" stroke-width="3" stroke-dasharray="8 8"/>
      ${bar(28, 176, 120)}${bar(R - 56, 176, 56)}${bar(28, 206, 96)}${bar(R - 44, 206, 44)}
      <path d="M28 248 H${R}" stroke="#CFCAC2" stroke-width="3" stroke-dasharray="8 8"/>
      ${T(28, 298, 27, 800, '#171717', 'Total')}${T(R, 298, 27, 800, '#171717', '₦10,500', 'text-anchor="end"')}
      <rect x="28" y="334" width="${R - 28}" height="64" rx="14" fill="#EDF8F1"/>
      <path d="M50 354 L60 364 L78 346" stroke="#16A34A" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      ${T(94, 374, 22, 700, '#15803D', 'Held safely')}`);
  }

  function pen() {
    const r = id('r'), c = id('c'), s = id('s');
    return svg(46, 500, `<defs>${lin(r, RUBBER)}${lin(c, CRIMSON)}${lin(s, STEEL)}</defs>
      <rect x="6" y="0" width="34" height="420" rx="17" fill="url(#${r})"/>
      <rect x="26" y="20" width="12" height="150" rx="6" fill="url(#${c})"/>
      <rect x="6" y="400" width="34" height="22" fill="url(#${s})"/>
      <path d="M8 420 H38 L26 486 H20 Z" fill="url(#${r})"/><path d="M20 484 H26 L23 500 Z" fill="#8E959C"/>`);
  }

  // ── the site ─────────────────────────────────────────────────────────────
  function hardHat() {
    const b = id('b'), d = id('d');
    // Employi's pin as a white sticker on the crown.
    const pin = 'M0 -58 C32 -58 58 -32 58 0 C58 34 18 70 0 92 C-18 70 -58 34 -58 0 C-58 -32 -32 -58 0 -58 Z M0 -26 A26 26 0 1 0 0.1 -26 Z';
    return svg(420, 400, `<defs>${lin(b, [[0, '#7A001B'], [0.5, '#A20025'], [1, '#7A001B']])}${rad(d, [[0, '#E8335A'], [0.45, '#BC002C'], [1, '#7A001B']], '.36', '.3', '.85')}</defs>
      <path d="M210 4 C330 4 416 92 416 210 C416 300 360 372 300 392 C260 400 160 400 120 392 C60 372 4 300 4 210 C4 92 90 4 210 4 Z" fill="url(#${b})"/>
      <path d="M120 392 C160 380 260 380 300 392" stroke="rgba(255,255,255,.18)" stroke-width="6" fill="none"/>
      <ellipse cx="210" cy="190" rx="160" ry="150" fill="url(#${d})"/>
      <path d="M182 46 V330 M238 46 V330" stroke="rgba(0,0,0,.16)" stroke-width="16" stroke-linecap="round"/>
      <path d="M176 52 V322 M232 52 V322" stroke="rgba(255,255,255,.2)" stroke-width="5" stroke-linecap="round"/>
      <path d="${pin}" fill="#FFF" fill-rule="evenodd" transform="translate(316 196) scale(.36)"/>`);
  }

  function glove(mirror = false) {
    const k = id('k'), c = id('c');
    const finger = (cx, top, rot) => `<rect x="${cx - 17}" y="${top}" width="34" height="${214 - top}" rx="17" transform="rotate(${rot} ${cx} 214)" fill="url(#${c})"/>`;
    // Laid as a pair with the thumbs out, so they never cross.
    return `<g transform="${mirror ? 'translate(250 0) scale(-1 1)' : 'translate(270 0)'}">
      <defs>${lin(k, [[0, '#B9B9B9'], [0.5, '#E2E2E2'], [1, '#B1B1B1']])}${lin(c, CRIMSON)}</defs>
      ${finger(52, 100, -10)}${finger(88, 56, -3)}${finger(124, 48, 3)}${finger(158, 76, 9)}
      <rect x="172" y="186" width="40" height="124" rx="20" transform="rotate(44 192 304)" fill="url(#${c})"/>
      <path d="M30 202 C30 186 42 178 56 178 H158 C172 178 182 188 182 204 L186 334 H30 Z" fill="url(#${k})"/>
      <path d="M36 220 C84 234 140 234 180 218" stroke="rgba(0,0,0,.09)" stroke-width="5" fill="none"/>
      <rect x="26" y="326" width="164" height="96" rx="18" fill="#262626"/>
      <path d="M48 336 V412 M72 336 V412 M96 336 V412 M120 336 V412 M144 336 V412 M168 336 V412" stroke="rgba(255,255,255,.1)" stroke-width="6"/>
    </g>`;
  }
  function gloves() { return svg(520, 430, glove(true) + glove()); }

  function torch() {
    const s = id('s'), r = id('r'), c = id('c');
    let knurl = '';
    for (let y = 300; y < 500; y += 14) knurl += `<path d="M28 ${y} H82" stroke="rgba(255,255,255,.08)" stroke-width="5"/>`;
    return svg(110, 560, `<defs>${lin(s, STEEL)}${lin(r, RUBBER)}${lin(c, CRIMSON)}</defs>
      <path d="M4 0 H106 V44 L86 122 H24 L4 44 Z" fill="url(#${s})"/>
      <rect x="4" y="0" width="102" height="14" rx="7" fill="rgba(255,255,255,.5)"/>
      <rect x="24" y="118" width="62" height="420" rx="14" fill="url(#${r})"/>${knurl}
      <rect x="40" y="172" width="30" height="56" rx="12" fill="url(#${c})"/>
      <rect x="20" y="528" width="70" height="32" rx="10" fill="url(#${s})"/>`);
  }

  function clipboard() {
    const r = id('r'), p = id('p'), s = id('s');
    const row = (y, label, done) => `<rect x="62" y="${y - 30}" width="38" height="38" rx="9" fill="${done ? '#A20025' : 'none'}" stroke="${done ? '#A20025' : '#3A3A3A'}" stroke-width="4"/>`
      + (done ? `<path d="M71 ${y - 11} L79 ${y - 3} L92 ${y - 19}" stroke="#FFF" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>` : '')
      + T(120, y, 31, 600, done ? '#171717' : '#6B6B6B', label);
    return svg(400, 580, `<defs>${lin(r, RUBBER)}${lin(p, PAPER, true)}${lin(s, STEEL)}</defs>
      <rect x="0" y="24" width="400" height="556" rx="28" fill="url(#${r})"/>
      <rect x="30" y="84" width="340" height="466" rx="8" fill="url(#${p})"/>
      ${T(62, 160, 34, 800, '#171717', 'Your job')}<path d="M62 184 H338" stroke="#E5E5E5" stroke-width="3"/>
      ${row(256, 'Accepted', true)}${row(332, 'On the way', true)}${row(408, 'Started', false)}${row(484, 'Done', false)}
      <path d="M124 0 H276 A14 14 0 0 1 290 14 V74 A14 14 0 0 1 276 88 H124 A14 14 0 0 1 110 74 V14 A14 14 0 0 1 124 0 Z" fill="url(#${s})"/>
      <rect x="170" y="18" width="60" height="18" rx="9" fill="rgba(0,0,0,.18)"/>`);
  }

  function tapeRoll() {
    const t = id('t');
    return svg(200, 200, `<defs>${rad(t, [[0.55, '#2A2A2A'], [0.8, '#151515'], [1, '#050505']], '.5', '.5', '.5')}</defs>
      <circle cx="100" cy="100" r="97" fill="url(#${t})"/>
      <circle cx="100" cy="100" r="80" fill="none" stroke="rgba(255,255,255,.05)" stroke-width="3"/>
      <circle cx="100" cy="100" r="66" fill="none" stroke="rgba(255,255,255,.05)" stroke-width="3"/>
      <circle cx="100" cy="100" r="56" fill="#D8D1C6"/><circle cx="100" cy="100" r="47" fill="#EAE5DE"/>`);
  }

  function zipTie() {
    let teeth = '';
    for (let y = 60; y < 450; y += 10) teeth += `<path d="M12 ${y} H28" stroke="rgba(255,255,255,.12)" stroke-width="3"/>`;
    return svg(40, 460, `<rect x="0" y="0" width="40" height="46" rx="8" fill="#151515"/><rect x="12" y="10" width="16" height="22" rx="3" fill="#3A3A3A"/>
      <path d="M11 44 H29 V444 L20 460 L11 444 Z" fill="#1E1E1E"/>${teeth}`);
  }

  // ── talking ──────────────────────────────────────────────────────────────
  function walkie(color = 'crimson') {
    const b = id('b'), r = id('r');
    const body = color === 'crimson' ? CRIMSON : RUBBER.map(([o, c]) => [o, c === '#3A3A3A' ? '#444' : c]);
    let grille = '';
    for (let y = 262; y < 392; y += 22) grille += `<rect x="40" y="${y}" width="120" height="10" rx="5" fill="rgba(0,0,0,.35)"/>`;
    return svg(200, 660, `<defs>${lin(b, body)}${lin(r, RUBBER)}</defs>
      <rect x="22" y="0" width="38" height="240" rx="19" fill="url(#${r})"/>
      <circle cx="146" cy="196" r="26" fill="url(#${r})"/>
      <rect x="0" y="210" width="200" height="450" rx="42" fill="url(#${b})"/>
      <rect x="12" y="222" width="176" height="14" rx="7" fill="rgba(255,255,255,.14)"/>
      ${grille}
      <rect x="40" y="420" width="120" height="66" rx="10" fill="#C6D2C9"/>
      ${T(100, 464, 28, 700, '#26302A', 'CH 01', 'text-anchor="middle" letter-spacing="2"')}
      <circle cx="62" cy="540" r="18" fill="rgba(0,0,0,.4)"/><circle cx="100" cy="540" r="18" fill="rgba(0,0,0,.4)"/><circle cx="138" cy="540" r="18" fill="rgba(0,0,0,.4)"/>
      <rect x="62" y="590" width="76" height="24" rx="12" fill="rgba(0,0,0,.4)"/>`);
  }
  const walkieCrimson = () => walkie('crimson');
  const walkieBlack = () => walkie('black');

  function notepad() {
    const p = id('p'), c = id('c'), s = id('s');
    let lines = '', rings = '';
    for (let y = 150; y < 490; y += 42) lines += `<path d="M30 ${y} H350" stroke="#E2DED7" stroke-width="2.5"/>`;
    for (let x = 44; x < 350; x += 26) rings += `<rect x="${x}" y="2" width="12" height="44" rx="6" fill="url(#${s})"/>`;
    return svg(380, 520, `<defs>${lin(p, PAPER, true)}${lin(c, CRIMSON)}${lin(s, STEEL)}</defs>
      <rect x="1" y="22" width="378" height="496" rx="14" fill="url(#${p})" stroke="rgba(0,0,0,.07)" stroke-width="2"/>
      <rect x="1" y="22" width="378" height="52" rx="14" fill="url(#${c})"/>
      ${lines}<path d="M66 96 V500" stroke="#E595A6" stroke-width="3"/>
      ${T(86, 140, 30, 700, '#262626', 'Sat, 9 AM')}
      <rect x="92" y="196" width="150" height="86" rx="10" fill="none" stroke="#3A3A3A" stroke-width="5"/>
      <circle cx="210" cy="239" r="26" fill="none" stroke="#3A3A3A" stroke-width="5"/>
      <path d="M106 214 H170 M106 232 H170 M106 250 H170" stroke="#3A3A3A" stroke-width="4"/>
      <path d="M256 240 H316 M300 224 L316 240 L300 256" stroke="#A20025" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      ${T(86, 350, 28, 600, '#3A3A3A', 'Gas top-up')}${T(86, 392, 28, 600, '#3A3A3A', 'Gate: blue')}
      ${rings}`);
  }

  function stickyNotes() {
    return svg(230, 230, `<rect x="0" y="0" width="230" height="230" rx="10" fill="#F2C4CE"/>
      <rect x="0" y="0" width="230" height="26" rx="10" fill="#E595A6"/>
      <path d="M150 230 L230 150 V220 A10 10 0 0 1 220 230 Z" fill="rgba(0,0,0,.06)"/>`);
  }

  // ── getting paid ─────────────────────────────────────────────────────────
  function toolbox() {
    const c = id('c'), r = id('r'), s = id('s');
    return svg(560, 340, `<defs>${lin(c, [[0, '#C4002F'], [0.5, '#A20025'], [1, '#7A001B']], true)}${lin(r, RUBBER)}${lin(s, STEEL)}</defs>
      <rect x="0" y="0" width="560" height="340" rx="30" fill="url(#${c})"/>
      <path d="M30 70 H530 M30 270 H530" stroke="rgba(0,0,0,.18)" stroke-width="6"/>
      <path d="M30 76 H530" stroke="rgba(255,255,255,.12)" stroke-width="3"/>
      <rect x="150" y="146" width="260" height="48" rx="24" fill="url(#${r})"/>
      <rect x="128" y="140" width="40" height="60" rx="10" fill="url(#${s})"/><rect x="392" y="140" width="40" height="60" rx="10" fill="url(#${s})"/>
      <rect x="80" y="300" width="70" height="40" rx="8" fill="url(#${s})"/><rect x="410" y="300" width="70" height="40" rx="8" fill="url(#${s})"/>`);
  }

  function wallet() {
    const g = id('g'), c = id('c');
    return svg(420, 320, `<defs>${lin(g, [[0, '#2B2B2B'], [1, '#101010']], true)}${lin(c, CRIMSON)}</defs>
      <rect x="40" y="0" width="300" height="120" rx="14" fill="url(#${c})"/>
      <rect x="0" y="40" width="420" height="280" rx="30" fill="url(#${g})"/>
      <rect x="16" y="56" width="388" height="248" rx="20" fill="none" stroke="#A20025" stroke-width="3" stroke-dasharray="10 8"/>
      <path d="M0 150 H420" stroke="rgba(255,255,255,.07)" stroke-width="3"/>`);
  }

  function pliers() {
    const s = id('s'), c = id('c');
    return svg(220, 640, `<defs>${lin(s, STEEL)}${lin(c, CRIMSON)}</defs>
      <path d="M96 226 C82 330 62 470 52 612" stroke="url(#${s})" stroke-width="34" fill="none" stroke-linecap="round"/>
      <path d="M124 226 C138 330 158 470 168 612" stroke="url(#${s})" stroke-width="34" fill="none" stroke-linecap="round"/>
      <path d="M84 322 C72 420 60 520 52 612" stroke="url(#${c})" stroke-width="46" fill="none" stroke-linecap="round"/>
      <path d="M136 322 C148 420 160 520 168 612" stroke="url(#${c})" stroke-width="46" fill="none" stroke-linecap="round"/>
      <path d="M110 4 C96 34 82 96 78 158 L110 206 L142 158 C138 96 124 34 110 4 Z" fill="url(#${s})"/>
      <path d="M110 12 V192" stroke="rgba(0,0,0,.3)" stroke-width="3"/>
      <path d="M94 110 H126 M92 128 H128 M90 146 H130" stroke="rgba(0,0,0,.15)" stroke-width="3"/>
      <circle cx="110" cy="212" r="28" fill="url(#${s})"/><circle cx="110" cy="212" r="10" fill="rgba(0,0,0,.25)"/>`);
  }

  return { idCard, magnifier, stamp, stampMark, priceTag, pencil, clip, multimeter, padlock, key, calendar, stopwatch, card, coin,
    receipt, pen, hardHat, gloves, torch, clipboard, tapeRoll, zipTie, walkieCrimson, walkieBlack, notepad, stickyNotes, toolbox, wallet, pliers };
})());
