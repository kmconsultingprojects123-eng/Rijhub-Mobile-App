'use strict';
// Artisans' tools, drawn top-down for a knolling layout (everything laid flat
// at right angles, the way a tradesman lays out a kit). Each returns an SVG
// string at its natural size, long axis vertical; the page scales and turns
// them. Brand palette only: crimson grips, black rubber, brushed steel.
const TOOLS = (() => {
  let uid = 0;
  const id = (p) => `${p}${++uid}`;
  const steel = (g, dir = 'h') => `<linearGradient id="${g}" ${dir === 'h' ? 'x1="0" y1="0" x2="1" y2="0"' : 'x1="0" y1="0" x2="0" y2="1"'}>
      <stop offset="0" stop-color="#9AA1A8"/><stop offset=".18" stop-color="#E9ECEF"/><stop offset=".42" stop-color="#C3C9CF"/>
      <stop offset=".7" stop-color="#F3F5F7"/><stop offset="1" stop-color="#8E959C"/></linearGradient>`;
  const crimson = (g) => `<linearGradient id="${g}" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#6F0019"/><stop offset=".25" stop-color="#C4002F"/><stop offset=".45" stop-color="#D21540"/>
      <stop offset=".75" stop-color="#A20025"/><stop offset="1" stop-color="#5E0015"/></linearGradient>`;
  const rubber = (g) => `<linearGradient id="${g}" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#0B0B0B"/><stop offset=".35" stop-color="#3A3A3A"/><stop offset=".6" stop-color="#202020"/><stop offset="1" stop-color="#070707"/></linearGradient>`;
  const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;

  function screwdriver() {
    const s = id('s'), c = id('c'), r = id('r');
    return svg(110, 780, `<defs>${steel(s)}${crimson(c)}${rubber(r)}</defs>
      <path d="M12 62 C12 10 32 0 55 0 C78 0 98 10 98 62 L95 300 C94 326 84 338 70 340 L40 340 C26 338 16 326 15 300 Z" fill="url(#${c})"/>
      <path d="M33 46 V296 M55 40 V302 M77 46 V296" stroke="rgba(0,0,0,.22)" stroke-width="7" stroke-linecap="round"/>
      <path d="M26 70 V280" stroke="rgba(255,255,255,.35)" stroke-width="5" stroke-linecap="round"/>
      <rect x="31" y="338" width="48" height="52" rx="6" fill="url(#${r})"/>
      <rect x="44" y="388" width="22" height="350" fill="url(#${s})"/>
      <path d="M44 736 H66 L63 774 H47 Z" fill="url(#${s})"/>
      <path d="M44 736 H66" stroke="rgba(0,0,0,.18)" stroke-width="2"/>`);
  }

  function spanner() {
    const s = id('s'), m = id('m');
    return svg(220, 900, `<defs>${steel(s)}
        <mask id="${m}"><rect width="220" height="900" fill="#fff"/>
          <circle cx="110" cy="112" r="52" fill="#000"/>
          <g transform="rotate(-15 110 790)"><rect x="66" y="790" width="88" height="160" fill="#000"/><circle cx="110" cy="790" r="44" fill="#000"/></g>
        </mask></defs>
      <g mask="url(#${m})">
        <circle cx="110" cy="112" r="100" fill="url(#${s})"/>
        <path d="M70 190 C78 260 82 330 80 450 C82 570 78 640 70 712 L150 712 C142 640 138 570 140 450 C138 330 142 260 150 190 Z" fill="url(#${s})"/>
        <circle cx="110" cy="790" r="102" fill="url(#${s})"/>
        <rect x="92" y="250" width="36" height="400" rx="18" fill="rgba(0,0,0,.08)"/>
        <circle cx="110" cy="112" r="64" fill="none" stroke="rgba(0,0,0,.12)" stroke-width="6"/>
      </g>
      <text x="110" y="232" text-anchor="middle" font-family="Inter" font-weight="700" font-size="26" fill="rgba(0,0,0,.32)">13</text>
      <text x="110" y="688" text-anchor="middle" font-family="Inter" font-weight="700" font-size="26" fill="rgba(0,0,0,.32)">13</text>`);
  }

  function hammer() {
    const s = id('s'), c = id('c'), r = id('r'), m = id('m');
    return svg(330, 880, `<defs>${steel(s, 'v')}${crimson(c)}${rubber(r)}
        <mask id="${m}"><rect width="330" height="130" fill="#fff"/><path d="M262 55 L330 44 V66 Z" fill="#000"/></mask></defs>
      <rect x="133" y="80" width="64" height="500" rx="20" fill="url(#${r})"/>
      <path d="M128 548 H202 L207 836 C207 864 190 878 165 878 C140 878 123 864 123 836 Z" fill="url(#${c})"/>
      <path d="M134 590 H196 M134 628 H196 M134 666 H196 M134 704 H196 M134 742 H196 M134 780 H196 M134 818 H196" stroke="rgba(0,0,0,.24)" stroke-width="7" stroke-linecap="round"/>
      <g mask="url(#${m})">
        <rect x="6" y="2" width="96" height="112" rx="18" fill="url(#${s})"/>
        <rect x="96" y="22" width="40" height="72" fill="url(#${s})"/>
        <rect x="124" y="8" width="84" height="100" rx="12" fill="url(#${s})"/>
        <path d="M204 22 C240 24 286 28 326 40 L326 70 C286 82 240 86 204 88 Z" fill="url(#${s})"/>
      </g>
      <rect x="6" y="2" width="18" height="112" rx="9" fill="rgba(255,255,255,.4)"/>
      <rect x="140" y="24" width="50" height="68" rx="8" fill="rgba(0,0,0,.1)"/>`);
  }

  function level() {
    const a = id('a'), c = id('c');
    return svg(120, 880, `<defs>
        <linearGradient id="${a}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#B9BEC4"/><stop offset=".3" stop-color="#EEF0F2"/><stop offset=".55" stop-color="#D3D7DB"/><stop offset="1" stop-color="#A4AAB0"/></linearGradient>
        ${crimson(c)}</defs>
      <rect x="8" y="0" width="104" height="880" rx="14" fill="url(#${a})"/>
      <rect x="8" y="0" width="104" height="64" rx="14" fill="url(#${c})"/><rect x="8" y="816" width="104" height="64" rx="14" fill="url(#${c})"/>
      <rect x="22" y="352" width="76" height="176" rx="14" fill="#1C1C1C"/>
      <rect x="33" y="370" width="54" height="140" rx="27" fill="#D7F0DF"/>
      <rect x="40" y="418" width="40" height="44" rx="20" fill="#FFF" opacity=".95"/>
      <path d="M33 408 H87 M33 472 H87" stroke="#1C1C1C" stroke-width="4"/>
      <circle cx="60" cy="190" r="30" fill="#1C1C1C"/><circle cx="60" cy="190" r="20" fill="#D7F0DF"/>
      <circle cx="60" cy="690" r="30" fill="#1C1C1C"/><circle cx="60" cy="690" r="20" fill="#D7F0DF"/>`);
  }

  function brush() {
    const s = id('s'), r = id('r');
    return svg(130, 760, `<defs>${steel(s)}${rubber(r)}</defs>
      <path d="M48 6 C56 0 74 0 82 6 L96 430 H34 Z" fill="url(#${r})"/>
      <circle cx="65" cy="52" r="12" fill="#EDE9E4"/>
      <rect x="22" y="428" width="86" height="120" rx="8" fill="url(#${s})"/>
      <path d="M22 456 H108 M22 520 H108" stroke="rgba(0,0,0,.18)" stroke-width="4"/>
      <path d="M24 546 H106 L112 690 C112 724 98 740 65 740 C32 740 18 724 18 690 Z" fill="#3B3431"/>
      <path d="M18 668 C40 676 52 660 65 672 C80 684 92 664 112 670 L112 690 C112 724 98 740 65 740 C32 740 18 724 18 690 Z" fill="#A20025"/>
      <path d="M38 556 V660 M52 556 V666 M65 556 V662 M78 556 V666 M92 556 V660" stroke="rgba(255,255,255,.08)" stroke-width="3"/>`);
  }

  function tape() {
    const c = id('c'), r = id('r');
    let ticks = '';
    for (let x = 280; x <= 640; x += 9) {
      const big = (x - 280) % 90 === 0, mid = (x - 280) % 45 === 0;
      ticks += `<path d="M${x} 162 V${big ? 190 : mid ? 182 : 174}" stroke="#1C1C1C" stroke-width="${big ? 3 : 2}"/>`;
      if (big && x > 280 && x < 620) ticks += `<text x="${x + 4}" y="216" font-family="Inter" font-weight="700" font-size="20" fill="#1C1C1C">${(x - 280) / 90}</text>`;
    }
    return svg(680, 300, `<defs>${crimson(c)}${rubber(r)}</defs>
      <rect x="270" y="160" width="390" height="70" fill="#F4EFE2"/>
      ${ticks}
      <rect x="648" y="152" width="16" height="86" rx="3" fill="#B9BEC4"/>
      <rect x="0" y="0" width="300" height="300" rx="70" fill="url(#${c})"/>
      <rect x="0" y="0" width="300" height="300" rx="70" fill="none" stroke="#151515" stroke-width="26" stroke-dasharray="230 210" stroke-dashoffset="60"/>
      <circle cx="150" cy="150" r="72" fill="#F7F7F7"/>
      <circle cx="150" cy="150" r="20" fill="#B9BEC4"/><path d="M138 150 H162 M150 138 V162" stroke="#6F767D" stroke-width="5"/>
      <rect x="232" y="118" width="68" height="64" rx="10" fill="#151515"/>`);
  }

  function bulb() {
    const g = id('g'), s = id('s');
    return svg(390, 210, `<defs>
        <radialGradient id="${g}" cx=".36" cy=".34" r=".72"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".62" stop-color="#FBF6EA"/><stop offset="1" stop-color="#E4DFD3"/></radialGradient>
        ${steel(s, 'v')}</defs>
      <path d="M112 8 C176 8 214 50 232 80 L252 80 V130 L232 130 C214 160 176 202 112 202 C50 202 4 158 4 105 C4 52 50 8 112 8 Z" fill="url(#${g})" stroke="rgba(0,0,0,.13)" stroke-width="3"/>
      <path d="M250 96 L200 100 L170 104 M250 114 L200 110 L170 106" stroke="#B9BEC4" stroke-width="4" fill="none"/>
      <path d="M170 92 V118" stroke="#C9CDD1" stroke-width="10" stroke-linecap="round"/>
      <path d="M150 90 L142 94 L150 98 L142 102 L150 106 L142 110 L150 114 L142 118" stroke="#8E959C" stroke-width="3.5" fill="none" stroke-linejoin="round"/>
      <path d="M150 90 L170 92 M150 118 L170 118" stroke="#9AA1A8" stroke-width="2.5"/>
      <path d="M58 52 C40 70 34 92 36 112" stroke="#FFF" stroke-width="9" fill="none" stroke-linecap="round" opacity=".9"/>
      <rect x="250" y="64" width="98" height="82" rx="10" fill="url(#${s})"/>
      <path d="M268 64 C262 84 262 126 268 146 M290 64 C284 84 284 126 290 146 M312 64 C306 84 306 126 312 146 M334 64 C328 84 328 126 334 146" stroke="rgba(0,0,0,.22)" stroke-width="5" fill="none"/>
      <rect x="346" y="80" width="22" height="50" rx="6" fill="#1C1C1C"/>
      <circle cx="376" cy="105" r="11" fill="url(#${s})"/>`);
  }

  function remote() {
    const g = id('g');
    let keys = '';
    for (let row = 0; row < 4; row++) for (let col = 0; col < 3; col++) keys += `<rect x="${38 + col * 46}" y="${300 + row * 46}" width="34" height="26" rx="13" fill="#DADDE0"/>`;
    return svg(200, 540, `<defs><linearGradient id="${g}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#E4E6E8"/><stop offset=".35" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E1E3E5"/></linearGradient></defs>
      <rect x="10" y="0" width="180" height="540" rx="64" fill="url(#${g})" stroke="rgba(0,0,0,.06)" stroke-width="2"/>
      <rect x="36" y="56" width="128" height="120" rx="16" fill="#C9D3CB"/>
      <text x="100" y="140" text-anchor="middle" font-family="Inter" font-weight="600" font-size="56" fill="#2A332C" letter-spacing="-1">24°</text>
      <circle cx="100" cy="230" r="30" fill="#A20025"/><path d="M100 214 V230 M88 222 A17 17 0 1 0 112 222" stroke="#FFF" stroke-width="5" fill="none" stroke-linecap="round"/>
      ${keys}`);
  }

  function nut() {
    const s = id('s');
    return svg(80, 80, `<defs>${steel(s)}</defs>
      <path d="M40 2 L73 21 V59 L40 78 L7 59 V21 Z" fill="url(#${s})" stroke="rgba(0,0,0,.12)" stroke-width="2"/>
      <circle cx="40" cy="40" r="16" fill="#EDE9E4" stroke="rgba(0,0,0,.18)" stroke-width="3"/>`);
  }

  function screw() {
    const s = id('s');
    return svg(70, 70, `<defs><radialGradient id="${s}" cx=".35" cy=".35" r=".75"><stop offset="0" stop-color="#F3F5F7"/><stop offset=".6" stop-color="#C3C9CF"/><stop offset="1" stop-color="#8E959C"/></radialGradient></defs>
      <circle cx="35" cy="35" r="32" fill="url(#${s})" stroke="rgba(0,0,0,.12)" stroke-width="2"/>
      <path d="M22 35 H48 M35 22 V48" stroke="rgba(0,0,0,.35)" stroke-width="6" stroke-linecap="round"/>`);
  }

  return { screwdriver, spanner, hammer, level, brush, tape, bulb, remote, nut, screw };
})();
