// Frame renderer for "Міжнародний менеджер: очікування vs реальність".
// draw(t) paints the frame at time t (seconds). window.TL holds timeline.json.
const W = 1080, H = 1920;
const cv = document.getElementById('c');
const mainCtx = cv.getContext('2d');
let ctx = mainCtx;
const off = document.createElement('canvas');
off.width = W; off.height = H;
const offCtx = off.getContext('2d');

const TL = window.TL;
const S = TL.scenes;
const C = TL.cues;

// ------------------------------------------------------------------ math
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, k) => a + (b - a) * k;
const prog = (t, a, d) => clamp((t - a) / d);
const eOut = k => 1 - Math.pow(1 - k, 3);
const eInOut = k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2);
const eBack = k => { const c1 = 1.70158, c3 = c1 + 1; return k <= 0 ? 0 : 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2); };
const rnd = i => { const x = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };

function wt(lid, needle, which = 0) {
  const hits = TL.lines[lid].words.filter(w => w.w.toLowerCase().includes(needle.toLowerCase()));
  return hits[which].s;
}

// ------------------------------------------------------------ primitives
const EMO = '"Noto Color Emoji"';
const font = (size, weight = 800, fam = 'Inter') => `${weight} ${size}px "${fam}", ${EMO}`;

function txt(s, x, y, o = {}) {
  ctx.save();
  ctx.font = font(o.size || 48, o.weight || 800, o.fam || 'Inter');
  ctx.textAlign = o.align || 'center';
  ctx.textBaseline = o.base || 'middle';
  ctx.globalAlpha *= (o.alpha ?? 1);
  if (o.ls) ctx.letterSpacing = o.ls + 'px';
  if (o.shadow) { ctx.shadowColor = o.shadow; ctx.shadowBlur = o.blur ?? 20; ctx.shadowOffsetY = o.sy ?? 0; }
  if (o.stroke) {
    ctx.lineJoin = 'round'; ctx.lineWidth = o.sw || 8; ctx.strokeStyle = o.stroke;
    ctx.strokeText(s, x, y);
    ctx.shadowBlur = 0; ctx.shadowColor = 'transparent';
  }
  ctx.fillStyle = o.color || '#fff';
  ctx.fillText(s, x, y);
  ctx.restore();
}

function measure(s, size, weight = 800, fam = 'Inter', ls = 0) {
  ctx.save();
  ctx.font = font(size, weight, fam);
  if (ls) ctx.letterSpacing = ls + 'px';
  const w = ctx.measureText(s).width;
  ctx.restore();
  return w;
}

// shrink font until it fits maxW
function txtFit(s, x, y, maxW, o = {}) {
  let size = o.size || 48;
  while (size > 16 && measure(s, size, o.weight || 800, o.fam || 'Inter', o.ls || 0) > maxW) size -= 2;
  txt(s, x, y, { ...o, size });
  return size;
}

// left-aligned text, vertically centred on y, wraps to 2 lines and shrinks to fit
function wrapFit(s, x, y, maxW, maxSize, minSize, o = {}) {
  const words = s.split(' ');
  for (let size = maxSize; size >= minSize; size -= 2) {
    if (measure(s, size, o.weight || 800) <= maxW) { txt(s, x, y, { ...o, size, align: 'left' }); return; }
    for (let cut = words.length - 1; cut >= 1; cut--) {
      const a = words.slice(0, cut).join(' '), b = words.slice(cut).join(' ');
      if (measure(a, size, o.weight || 800) <= maxW && measure(b, size, o.weight || 800) <= maxW) {
        const lh = size * 1.12;
        txt(a, x, y - lh / 2, { ...o, size, align: 'left' });
        txt(b, x, y + lh / 2, { ...o, size, align: 'left' });
        return;
      }
    }
  }
  txt(s, x, y, { ...o, size: minSize, align: 'left' });
}

function emoji(e, x, y, size, o = {}) {
  ctx.save();
  ctx.translate(x, y);
  if (o.rot) ctx.rotate(o.rot);
  const sc = o.scale ?? 1;
  ctx.scale(sc, sc);
  ctx.globalAlpha *= (o.alpha ?? 1);
  if (o.glow) { ctx.shadowColor = o.glow; ctx.shadowBlur = o.blur ?? 40; }
  ctx.font = `${size}px ${EMO}`;
  ctx.fillStyle = '#000'; // colour glyphs are modulated by the fill alpha, so keep it opaque
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(e, 0, size * 0.04);
  ctx.restore();
}

function rr(x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, Math.max(0, w), h, r); }

function card(x, y, w, h, o = {}) {
  ctx.save();
  ctx.globalAlpha *= (o.alpha ?? 1);
  if (o.glow) { ctx.shadowColor = o.glow; ctx.shadowBlur = o.blur ?? 40; }
  rr(x, y, w, h, o.r ?? 32);
  ctx.fillStyle = o.fill || 'rgba(255,255,255,0.08)';
  ctx.fill();
  ctx.shadowBlur = 0; ctx.shadowColor = 'transparent';
  if (o.stroke) { ctx.lineWidth = o.sw || 3; ctx.strokeStyle = o.stroke; ctx.stroke(); }
  ctx.restore();
}

function tf(x, y, o, fn) {
  ctx.save();
  ctx.translate(x, y);
  if (o.rot) ctx.rotate(o.rot);
  if (o.scale !== undefined) ctx.scale(o.scale, o.scale);
  if (o.sx !== undefined) ctx.scale(o.sx, o.sy ?? 1);
  ctx.globalAlpha *= (o.alpha ?? 1);
  fn();
  ctx.restore();
}

function grad(x0, y0, x1, y1, cols) {
  const g = ctx.createLinearGradient(x0, y0, x1, y1);
  cols.forEach((c, i) => g.addColorStop(i / (cols.length - 1), c));
  return g;
}

function chip(label, x, y, o = {}) {
  const size = o.size || 46;
  const ls = o.ls ?? 2;
  const w = measure(label, size, 900, 'Inter', ls) + size * 1.4;
  const h = size * 1.75;
  if ((o.scale ?? 1) <= 0) return;
  tf(x, y, { rot: o.rot || 0, scale: o.scale ?? 1, alpha: o.alpha ?? 1 }, () => {
    ctx.save();
    if (o.glow) { ctx.shadowColor = o.glow; ctx.shadowBlur = 40; }
    rr(-w / 2, -h / 2, w, h, h / 2);
    ctx.fillStyle = grad(-w / 2, 0, w / 2, 0, o.bg || ['#FFF1A8', '#FFC24B']);
    ctx.fill();
    ctx.restore();
    txt(label, 0, 3, { size, weight: 900, color: o.fg || '#2A0E61', ls });
  });
}

function blob(x, y, r, col) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, col);
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
}

function sparkle(x, y, s, a, col = '#FFF7D6') {
  if (a <= 0) return;
  ctx.save();
  ctx.globalAlpha *= a;
  ctx.translate(x, y);
  ctx.fillStyle = col;
  ctx.beginPath();
  for (let k = 0; k < 8; k++) {
    const ang = k * Math.PI / 4, r = k % 2 ? s * 0.22 : s;
    ctx.lineTo(Math.cos(ang) * r, Math.sin(ang) * r);
  }
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

// --------------------------------------------------------- shared pieces
const GOLD = ['#FFF1A8', '#FFC24B'];
const CYAN = ['#2EE6D6', '#4D7CFE'];

function realityChip(t, t0, label = 'РЕАЛЬНІСТЬ 💼') {
  if (t < t0) return;
  const k = eOut(prog(t, t0, 0.28));
  chip(label, 540, 255, { bg: CYAN, fg: '#06102A', size: 48, rot: lerp(0.12, -0.04, k), scale: lerp(2.4, 1, k),
    alpha: clamp((t - t0) / 0.08), glow: 'rgba(46,230,214,0.7)' });
}

function expectChip(t, t0, label, bg = GOLD, fg = '#3A1060', glow = 'rgba(255,200,80,0.6)') {
  chip(label, 540, 255, { bg, fg, size: 46, rot: -0.06, scale: eBack(prog(t, t0, 0.3)), glow });
}

function achievement(t, t0, title, line, y = 1190) {
  if (t < t0) return;
  const k = eBack(prog(t, t0, 0.4));
  tf(540, y + lerp(80, 0, eOut(prog(t, t0, 0.3))), { scale: lerp(0.6, 1, k), alpha: clamp((t - t0) / 0.1) }, () => {
    card(-430, -80, 860, 160, { fill: 'rgba(12,14,40,0.94)', stroke: '#FFC24B', sw: 4, r: 34, glow: 'rgba(255,194,75,0.55)' });
    emoji('🏆', -352, -2, 88);
    txt(title, -282, -38, { size: 28, weight: 900, color: '#FFC24B', align: 'left', ls: 3 });
    txtFit(line, -282, 12, 670, { size: 44, weight: 900, color: '#fff', align: 'left' });
    const kb = eOut(prog(t, t0 + 0.2, 0.7));
    rr(-282, 50, 670, 12, 6); ctx.fillStyle = 'rgba(255,255,255,0.15)'; ctx.fill();
    rr(-282, 50, 670 * kb, 12, 6); ctx.fillStyle = '#FFC24B'; ctx.fill();
  });
}

function bgReality(t, variant = 0) {
  ctx.fillStyle = grad(0, 0, 0, H, ['#060A1E', '#0D1640', '#071029']);
  ctx.fillRect(0, 0, W, H);
  blob(220 + 120 * Math.sin(t * 0.6), 520 + 80 * Math.cos(t * 0.5), 560,
    variant ? 'rgba(160,80,255,0.38)' : 'rgba(46,230,214,0.26)');
  blob(880 + 90 * Math.cos(t * 0.45), 1250 + 120 * Math.sin(t * 0.4), 620, 'rgba(77,124,254,0.36)');
  blob(600 + 200 * Math.sin(t * 0.3), 1750, 520, variant ? 'rgba(46,230,214,0.2)' : 'rgba(160,80,255,0.24)');
  ctx.fillStyle = 'rgba(255,255,255,0.07)';
  const o = (t * 20) % 60;
  for (let y = -60 + o; y < H; y += 60) for (let x = 30; x < W; x += 60) ctx.fillRect(x, y, 3, 3);
}

function vignette() {
  const g = ctx.createRadialGradient(540, 900, 500, 540, 960, 1250);
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.38)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
}

// ------------------------------------------------- S1: expectation (glam)
function skyline() {
  const base = 1520;
  ctx.fillStyle = '#2A0B3D';
  let x = -20, i = 0;
  while (x < W + 20) {
    const w = 60 + rnd(i) * 90, h = 110 + rnd(i + 50) * 230;
    ctx.fillRect(x, base - h, w + 2, h + 500);
    x += w; i++;
  }
  // tall tower with a stepped spire
  const bx = 880;
  const pts = [[-75, 0], [-60, -260], [-42, -260], [-34, -420], [-20, -420], [-12, -560], [-4, -640], [0, -760]];
  ctx.beginPath();
  ctx.moveTo(bx + pts[0][0], base);
  pts.forEach(([dx, dy]) => ctx.lineTo(bx + dx, base + dy));
  [...pts].reverse().forEach(([dx, dy]) => ctx.lineTo(bx - dx, base + dy));
  ctx.closePath();
  ctx.fill();
  ctx.fillRect(0, base, W, H - base);
  // windows
  for (let k = 0; k < 70; k++) {
    const wx = rnd(k + 300) * W, wy = base - 20 - rnd(k + 400) * 200;
    ctx.fillStyle = `rgba(255,214,120,${0.25 + 0.5 * rnd(k + 500)})`;
    ctx.fillRect(wx, wy, 6, 9);
  }
}

function bgExpect(t) {
  const g = grad(0, 0, 0, H, ['#2A0E61', '#7A1E86', '#D23F86', '#FF7A59', '#FFC56B', '#FFD98A']);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  const sx = 540, sy = 1180, sr = 300;
  blob(sx, sy, 700, 'rgba(255,230,150,0.5)');
  ctx.save();
  ctx.beginPath(); ctx.arc(sx, sy, sr, 0, Math.PI * 2); ctx.clip();
  ctx.fillStyle = grad(0, sy - sr, 0, sy + sr, ['#FFF6B8', '#FFB36B', '#FF5E8A']);
  ctx.fillRect(sx - sr, sy - sr, 2 * sr, 2 * sr);
  ctx.fillStyle = g; // stripes cut with the background gradient itself
  for (let i = 0; i < 8; i++) {
    const y = sy + 10 + i * 40 + ((t * 25) % 40);
    ctx.fillRect(sx - sr, y, 2 * sr, 4 + i * 2.2);
  }
  ctx.restore();
  skyline();
  for (let i = 0; i < 26; i++) {
    sparkle(rnd(i) * W, 150 + rnd(i + 99) * 900, 10 + rnd(i + 7) * 18, Math.sin(t * 3 + i * 1.7));
  }
}

function sceneExpect(t) {
  bgExpect(t);
  // airplane with contrail
  const pk = prog(t, 0, 5.4);
  const ax = lerp(-160, 1240, pk), ay = lerp(1080, 640, pk);
  ctx.save();
  ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 8; ctx.lineCap = 'round';
  ctx.setLineDash([34, 22]);
  ctx.beginPath(); ctx.moveTo(-160, 1080); ctx.lineTo(ax - 50, ay + 16); ctx.stroke();
  ctx.restore();
  emoji('✈️', ax, ay, 110, { rot: 0.47 });

  txt('International Business: My Future', 540, 240, { size: 34, weight: 700, color: 'rgba(255,255,255,0.92)', ls: 1,
    alpha: eOut(prog(t, 0, 0.4)) });
  tf(540, 345, { scale: eBack(prog(t, 0.0, 0.45)) }, () =>
    txt('МІЖНАРОДНИЙ', 0, 0, { size: 100, weight: 900, shadow: 'rgba(60,0,80,0.6)', blur: 30, sy: 8 }));
  tf(540, 465, { scale: eBack(prog(t, 0.12, 0.45)) }, () =>
    txt('МЕНЕДЖЕР', 0, 0, { size: 132, weight: 900, color: '#FFE45C', shadow: 'rgba(60,0,80,0.6)', blur: 30, sy: 8 }));
  chip('ОЧІКУВАННЯ ✨', 540, 610, { bg: GOLD, fg: '#3A1060', size: 50, rot: -0.07, scale: eBack(prog(t, 0.32, 0.35)),
    glow: 'rgba(255,200,80,0.8)' });

  const kS = eBack(prog(t, 0.2, 0.5));
  emoji('😎', 540, 880 + Math.sin(t * 3) * 12, 240, { scale: kS, rot: Math.sin(t * 2) * 0.05 });
  const kava = wt('L1', 'кава');
  emoji('☕', 215, 1010 + Math.sin(t * 3 + 1) * 10, 150, { scale: eBack(prog(t, kava - 0.1, 0.35)) });
  emoji('🥂', 865, 1010 + Math.sin(t * 3 + 2) * 10, 150, { scale: eBack(prog(t, C.biz - 0.1, 0.35)) });
  chip('BUSINESS CLASS ✈️', 540, 1130, { bg: ['#FFFFFF', '#FFE6F1'], fg: '#7A1E86', size: 36, rot: 0.03,
    scale: eBack(prog(t, C.biz + 0.05, 0.3)) });
  emoji('📸', 860, 760, 120, { scale: eBack(prog(t, C.selfie - 0.05, 0.3)), rot: 0.15 });
  chip('📍 DUBAI', 235, 760, { bg: ['#FFFFFF', '#FFF1D6'], fg: '#B5338F', size: 36, rot: -0.08,
    scale: eBack(prog(t, C.dubai - 0.05, 0.3)) });
  // camera flash
  if (t > C.selfie && t < C.selfie + 0.3) {
    ctx.fillStyle = `rgba(255,255,255,${0.85 * (1 - (t - C.selfie) / 0.3)})`;
    ctx.fillRect(0, 0, W, H);
  }
}

// ------------------------------------------------ record-scratch freeze
function sceneFreeze(t) {
  ctx = offCtx;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  sceneExpect(S.scratch - 0.001);
  ctx = mainCtx;
  ctx.save();
  ctx.filter = 'grayscale(0.85) contrast(1.15) brightness(0.9)';
  ctx.drawImage(off, 0, 0);
  ctx.restore();
  const fr = Math.floor(t * 30);
  for (let i = 0; i < 8; i++) {
    const y = Math.floor(rnd(i * 3 + fr) * H), h = 16 + rnd(i * 7 + fr) * 80;
    const dx = (rnd(i * 13 + fr) - 0.5) * 140;
    ctx.drawImage(off, 0, y, W, h, dx, y, W, h);
  }
  const kx = eBack(prog(t, S.scratch + 0.04, 0.2));
  if (kx > 0) {
    tf(540, 880, { scale: kx, rot: -0.1 }, () => {
      ctx.strokeStyle = '#FF2E4D'; ctx.lineWidth = 46; ctx.lineCap = 'round';
      ctx.shadowColor = 'rgba(255,0,60,0.8)'; ctx.shadowBlur = 30;
      ctx.beginPath();
      ctx.moveTo(-190, -190); ctx.lineTo(190, 190);
      ctx.moveTo(190, -190); ctx.lineTo(-190, 190);
      ctx.stroke();
    });
  }
  chip('ЗУПИНИСЬ ✋', 540, 1150, { bg: ['#FF2E4D', '#FF6B3D'], fg: '#fff', size: 50, rot: 0.04,
    scale: eBack(prog(t, S.scratch + 0.08, 0.2)) });
}

// ------------------------------------------------- S2: time zones (reality)
function sceneZones(t) {
  bgReality(t);
  realityChip(t, S.S2 + 0.02);
  const run = (a, b, from, to) => lerp(from, to, eInOut(prog(t, a, b - a)));
  let mins;
  if (t < C.twelve - 0.45) mins = 540;
  else if (t < C.six - 0.45) mins = run(C.twelve - 0.45, C.twelve, 540, 720);
  else mins = run(C.six - 0.45, C.six, 720, 1080);
  const str = String(Math.floor(mins / 60)).padStart(2, '0') + ':' + String(Math.floor(mins % 60)).padStart(2, '0');
  const clockE = mins < 700 ? '🕘' : mins < 1000 ? '🕛' : '🕕';
  tf(540, 430, { scale: eBack(prog(t, S.S2 + 0.25, 0.35)) }, () => {
    card(-330, -95, 660, 190, { fill: 'rgba(10,20,60,0.78)', stroke: 'rgba(46,230,214,0.85)', sw: 4, r: 40,
      glow: 'rgba(46,230,214,0.45)' });
    emoji(clockE, -220, 0, 110);
    txt(str, 70, 6, { size: 140, weight: 800, fam: 'JetBrains Mono', color: '#E9FFFD', shadow: 'rgba(46,230,214,0.9)', blur: 25 });
  });
  const calls = [
    { cue: C.warsaw, flag: '🇵🇱', city: 'Варшава', time: '09:00', hi: 'Dzień dobry!' },
    { cue: C.shanghai, flag: '🇨🇳', city: 'Шанхай', time: '12:00', hi: 'Nǐ hǎo!' },
    { cue: C.toronto, flag: '🇨🇦', city: 'Торонто', time: '18:00', hi: 'Hello!' },
  ];
  calls.forEach((c, i) => {
    const t0 = c.cue - 0.12;
    if (t < t0) return;
    const k = eOut(prog(t, t0, 0.35));
    const y = 580 + i * 175;
    const active = (i === calls.length - 1 || t < calls[i + 1].cue - 0.12) && t < TL.lines.L3.start;
    const x = lerp(1100, 80, k);
    const al = active ? 1 : 0.62;
    card(x, y, 860, 160, { fill: active ? 'rgba(46,230,214,0.15)' : 'rgba(255,255,255,0.07)',
      stroke: active ? '#2EE6D6' : 'rgba(255,255,255,0.15)', sw: 3, r: 36,
      glow: active ? 'rgba(46,230,214,0.35)' : null, alpha: al });
    ctx.save();
    ctx.globalAlpha = al;
    emoji(c.flag, x + 92, y + 80, 90);
    txt(c.city, x + 170, y + 58, { size: 52, weight: 900, align: 'left' });
    txt('📞 дзвінок о ' + c.time, x + 170, y + 114, { size: 30, weight: 700, color: '#7FF5EA', align: 'left' });
    ctx.restore();
    const kb = eBack(prog(t, c.cue + 0.12, 0.3));
    if (kb > 0) {
      tf(x + 690, y + 80, { scale: kb, rot: -0.05, alpha: al }, () => {
        const w = measure(c.hi, 40, 900) + 50;
        card(-w / 2, -42, w, 84, { fill: '#FFFFFF', r: 26 });
        ctx.beginPath(); ctx.moveTo(-w / 2 + 20, 30); ctx.lineTo(-w / 2 - 6, 52); ctx.lineTo(-w / 2 + 48, 38);
        ctx.fillStyle = '#FFFFFF'; ctx.fill();
        txt(c.hi, 0, 2, { size: 40, weight: 900, color: '#0D1640' });
      });
    }
  });
  achievement(t, C.deal_skill, 'НАВИЧКУ ВІДКРИТО', 'Крос-культурна комунікація');
}

// ---------------------------------------------------- S3a: boring tables
function sceneBoring(t) {
  ctx.fillStyle = grad(0, 0, 0, H, ['#26262B', '#3E3E46', '#2A2A30']);
  ctx.fillRect(0, 0, W, H);
  expectChip(t, S.S3 + 0.03, 'ОЧІКУВАННЯ 🥱', ['#E6E6E6', '#A4A4AE'], '#222', 'rgba(255,255,255,0.25)');
  const x0 = 100, y0 = 380, cw = 880 / 6, ch = 62, rows = 12;
  ctx.save();
  ctx.globalAlpha = eOut(prog(t, S.S3, 0.25));
  ctx.fillStyle = '#E9E9EC'; ctx.fillRect(x0, y0, 880, ch * rows);
  ctx.fillStyle = '#C9C9D0'; ctx.fillRect(x0, y0, 880, ch);
  ctx.strokeStyle = '#B5B5BD'; ctx.lineWidth = 2;
  for (let c = 0; c <= 6; c++) { ctx.beginPath(); ctx.moveTo(x0 + c * cw, y0); ctx.lineTo(x0 + c * cw, y0 + ch * rows); ctx.stroke(); }
  for (let r = 0; r <= rows; r++) { ctx.beginPath(); ctx.moveTo(x0, y0 + r * ch); ctx.lineTo(x0 + 880, y0 + r * ch); ctx.stroke(); }
  ctx.restore();
  ctx.save();
  ctx.globalAlpha = eOut(prog(t, S.S3, 0.25));
  'ABCDEF'.split('').forEach((L, c) => txt(L, x0 + c * cw + cw / 2, y0 + ch / 2, { size: 28, weight: 800, color: '#555' }));
  for (let r = 1; r < rows; r++) for (let c = 0; c < 6; c++) {
    const v = Math.floor(rnd(r * 17 + c * 3) * 9000 + 100);
    txt(String(v), x0 + c * cw + cw / 2, y0 + r * ch + ch / 2, { size: 26, weight: 500, fam: 'JetBrains Mono', color: '#777' });
  }
  ctx.restore();
  const kk = eBack(prog(t, S.S3 + 0.15, 0.4));
  emoji('🥱', 540, 760 + Math.sin(t * 2) * 8, 250, { scale: kk * (1 + 0.04 * Math.sin(t * 1.5)) });
  for (let i = 0; i < 3; i++) {
    const ph = ((t - S.S3) * 0.8 + i / 3) % 1;
    txt('z', 690 + ph * 120 + i * 10, 640 - ph * 260, { size: 50 + i * 14, weight: 900, color: '#fff', alpha: Math.sin(ph * Math.PI) });
  }
}

// ------------------------------------------------------ S3b: trade quest
function bez(p0, p1, p2, u) {
  const a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u;
  return [a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]];
}

function stamp(t, t0, l1, l2, x, y, col = '#2EE68A', rot = -0.14) {
  if (t < t0) return;
  const k = prog(t, t0, 0.16);
  tf(x, y, { scale: lerp(2.6, 1, eOut(k)), rot, alpha: clamp((t - t0) / 0.06) }, () => {
    const w = 760, h = 240;
    ctx.save();
    ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 30;
    rr(-w / 2, -h / 2, w, h, 30); ctx.fillStyle = 'rgba(4,28,22,0.93)'; ctx.fill();
    ctx.shadowBlur = 0;
    ctx.strokeStyle = col; ctx.lineWidth = 10; ctx.stroke();
    rr(-w / 2 + 18, -h / 2 + 18, w - 36, h - 36, 20); ctx.lineWidth = 4; ctx.stroke();
    ctx.restore();
    txtFit(l1, 0, -34, w - 80, { size: 60, weight: 900, color: col, ls: 2 });
    txt(l2, 0, 50, { size: 58, weight: 900 });
  });
}

function sceneQuest(t) {
  bgReality(t);
  realityChip(t, S.S3b + 0.02);
  tf(540, 368, { scale: eBack(prog(t, C.quest - 0.1, 0.35)) }, () =>
    txtFit('КВЕСТ: МІЖНАРОДНА УГОДА 🌍', 0, 0, 900, { size: 52, weight: 900, shadow: 'rgba(77,124,254,0.9)', blur: 25 }));
  const kr = eOut(prog(t, S.S3b + 0.1, 0.35));
  ctx.save();
  ctx.globalAlpha = kr;
  card(80, 440, 860, 220, { fill: 'rgba(10,20,60,0.7)', stroke: 'rgba(77,124,254,0.6)', sw: 3, r: 36 });
  txt('⚓ Одеса', 120, 488, { size: 36, weight: 900, align: 'left' });
  txt('Інший континент 🌎', 900, 488, { size: 36, weight: 900, align: 'right' });
  const P0 = [165, 605], P1 = [510, 470], P2 = [855, 605];
  ctx.strokeStyle = 'rgba(46,230,214,0.35)'; ctx.lineWidth = 6; ctx.setLineDash([16, 14]);
  ctx.beginPath(); ctx.moveTo(...P0); ctx.quadraticCurveTo(...P1, ...P2); ctx.stroke();
  ctx.setLineDash([]);
  const u = eInOut(prog(t, C.quest, C.deal - C.quest));
  ctx.strokeStyle = '#2EE6D6'; ctx.lineWidth = 8; ctx.lineCap = 'round';
  ctx.shadowColor = 'rgba(46,230,214,0.9)'; ctx.shadowBlur = 16;
  ctx.beginPath();
  for (let i = 0; i <= 40; i++) { const p = bez(P0, P1, P2, (u * i) / 40); i ? ctx.lineTo(...p) : ctx.moveTo(...p); }
  ctx.stroke();
  ctx.shadowBlur = 0;
  [P0, P2].forEach(p => { ctx.beginPath(); ctx.arc(p[0], p[1], 12, 0, Math.PI * 2); ctx.fillStyle = '#2EE6D6'; ctx.fill(); });
  ctx.strokeStyle = 'rgba(120,170,255,0.45)'; ctx.lineWidth = 4;
  ctx.beginPath();
  for (let x = 110; x <= 910; x += 6) { const y = 638 + Math.sin(x * 0.05 + t * 4) * 5; x === 110 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); }
  ctx.stroke();
  ctx.restore();
  const sp = bez(P0, P1, P2, u);
  emoji('🚢', sp[0], sp[1] - 34 + Math.sin(t * 5) * 4, 78, { alpha: kr });

  const items = [['📦', 'Вантаж', C.cargo], ['🚚', 'Логістика', C.logistics], ['🛃', 'Мито', C.duty], ['💱', 'Курс валют', C.fx]];
  items.forEach(([e, label, cue], i) => {
    if (t < cue - 0.05) return;
    const k = eOut(prog(t, cue - 0.05, 0.25));
    const y = 700 + i * 98, x = lerp(-300, 80, k);
    card(x, y, 860, 86, { fill: 'rgba(255,255,255,0.08)', stroke: 'rgba(255,255,255,0.14)', sw: 2, r: 26, alpha: k });
    emoji(e, x + 60, y + 43, 54, { alpha: k });
    txt(label, x + 115, y + 46, { size: 44, weight: 800, align: 'left', alpha: k });
    ctx.save();
    ctx.globalAlpha = k;
    ctx.beginPath(); ctx.arc(x + 800, y + 43, 28, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 4; ctx.stroke();
    const kc = eBack(prog(t, cue + 0.2, 0.25));
    if (kc > 0) tf(x + 800, y + 43, { scale: kc }, () => {
      ctx.beginPath(); ctx.arc(0, 0, 30, 0, Math.PI * 2); ctx.fillStyle = '#2EE68A'; ctx.fill();
      ctx.strokeStyle = '#05210F'; ctx.lineWidth = 7; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.beginPath(); ctx.moveTo(-13, 1); ctx.lineTo(-4, 11); ctx.lineTo(14, -10); ctx.stroke();
    });
    ctx.restore();
  });
  stamp(t, C.deal, 'УГОДУ УКЛАДЕНО!', '🤝 🌍 ✅', 540, 880);
  achievement(t, C.deal + 0.55, 'НАВИЧКИ ВІДКРИТО', 'Міжнародна торгівля і логістика');
}

// ------------------------------------------------------- S4a: AI panic
function stripes(y, h, t) {
  ctx.save();
  ctx.beginPath(); ctx.rect(0, y, W, h); ctx.clip();
  ctx.fillStyle = '#FFD23F'; ctx.fillRect(0, y, W, h);
  ctx.fillStyle = '#111';
  const o = ((t * 120) % 80 + 80) % 80;
  for (let i = -3; i < W / 80 + 3; i++) {
    const sx = i * 80 + o;
    ctx.beginPath();
    ctx.moveTo(sx, y + h); ctx.lineTo(sx + 40, y + h); ctx.lineTo(sx + 40 + h, y); ctx.lineTo(sx + h, y);
    ctx.closePath(); ctx.fill();
  }
  ctx.restore();
}

function sceneAlarm(t) {
  ctx.fillStyle = grad(0, 0, 0, H, ['#1A0208', '#3D0612', '#1A0208']);
  ctx.fillRect(0, 0, W, H);
  const pulse = 0.5 + 0.5 * Math.sin((t - S.S4) * Math.PI * 5);
  blob(540, 780, 720, `rgba(255,30,60,${0.22 + 0.25 * pulse})`);
  stripes(330, 56, t);
  stripes(1225, 56, -t);
  expectChip(t, S.S4 + 0.03, 'ОЧІКУВАННЯ 😱', ['#FFC2C2', '#FF4D6D'], '#2A0010', 'rgba(255,60,90,0.6)');
  const sh = Math.sin(t * 60) * 6;
  emoji('🤖', 540 + sh, 770, 290, { scale: eBack(prog(t, S.S4 + 0.05, 0.35)), glow: 'rgba(255,40,70,0.9)', blur: 60 });
  tf(540, 1095, { scale: eBack(prog(t, S.S4 + 0.35, 0.3)), rot: -0.03 }, () =>
    txtFit('ШІ ЗАБЕРЕ РОБОТУ?!', 0, 0, 880, { size: 80, weight: 900, stroke: '#C4002B', sw: 14 }));
}

// ----------------------------------------------------- S4b: AI reality
function sceneAI(t) {
  bgReality(t);
  realityChip(t, S.S4b + 0.02);
  emoji('🤖', 225, 555 + Math.sin(t * 2.5) * 6, 190, { scale: eBack(prog(t, S.S4b + 0.05, 0.35)),
    glow: 'rgba(46,230,214,0.8)', blur: 40 });
  [['🌐 Перекладає', C.translate, 470], ['🧮 Рахує', C.calc, 630]].forEach(([s, cue, y]) => {
    const kb = eBack(prog(t, cue - 0.08, 0.3));
    if (kb <= 0) return;
    tf(375, y, { scale: kb }, () => {
      const w = measure(s, 46, 900) + 140;
      card(0, -55, w, 110, { fill: '#EFFFFD', r: 30 });
      ctx.beginPath(); ctx.moveTo(4, -12); ctx.lineTo(-30, 18); ctx.lineTo(12, 26); ctx.closePath();
      ctx.fillStyle = '#EFFFFD'; ctx.fill();
      txt(s, 34, 3, { size: 46, weight: 900, color: '#06283D', align: 'left' });
      txt('✓', w - 48, 3, { size: 54, weight: 900, color: '#0BB07B' });
    });
  });
  const kh = eBack(prog(t, C.people - 0.1, 0.4));
  if (kh > 0) {
    ctx.save();
    ctx.globalAlpha = clamp(kh);
    for (let i = 0; i < 12; i++) {
      const a = i * Math.PI / 6 + t * 0.6;
      ctx.fillStyle = 'rgba(255,228,92,0.10)';
      ctx.beginPath(); ctx.moveTo(540, 900);
      ctx.arc(540, 900, 420, a, a + 0.18); ctx.closePath(); ctx.fill();
    }
    ctx.strokeStyle = 'rgba(255,228,92,0.9)'; ctx.lineWidth = 8;
    ctx.shadowColor = 'rgba(255,228,92,0.9)'; ctx.shadowBlur = 40;
    ctx.beginPath(); ctx.arc(540, 900, 165 + 8 * Math.sin(t * 6), 0, Math.PI * 2); ctx.stroke();
    ctx.restore();
    emoji('🤝', 540, 900, 200, { scale: kh });
  }
  achievement(t, C.people + 0.05, 'ТВОЯ СУПЕРСИЛА', 'Переговори та робота з людьми');
}

// ------------------------------------------------------- S5: careers
function sceneCareers(t) {
  bgReality(t, 1);
  tf(540, 300, { scale: eBack(prog(t, S.S5 + 0.02, 0.35)) }, () =>
    txt('КИМ ПРАЦЮВАТИ? 🚀', 0, 0, { size: 76, weight: 900, shadow: 'rgba(160,80,255,0.9)', blur: 30 }));
  const jobs = [['📦', 'Експорт-менеджер'], ['🚢', 'Логіст міжнародних перевезень'], ['🌍', 'Бренд-менеджер глобальної компанії'],
    ['📈', 'Аналітик зарубіжних ринків'], ['🚀', 'Власний бізнес на весь світ']];
  const cues = ['a', 'b', 'c', 'd', 'e'].map(k => C['job_' + k]);
  const allOn = t > TL.lines.L9e.end;
  jobs.forEach(([e, label], i) => {
    const t0 = cues[i] - 0.08;
    if (t < t0) return;
    const k = eBack(prog(t, t0, 0.38));
    const y = 400 + i * 172;
    const active = allOn || i === jobs.length - 1 || t < cues[i + 1] - 0.08;
    const x = lerp(-900, 80, k);
    card(x, y, 860, 152, { fill: active ? 'rgba(46,230,214,0.16)' : 'rgba(255,255,255,0.07)',
      stroke: active ? '#2EE6D6' : 'rgba(255,255,255,0.12)', sw: 3, r: 34, glow: active ? 'rgba(46,230,214,0.45)' : null });
    txt(String(i + 1).padStart(2, '0'), x + 58, y + 78, { size: 34, weight: 800, fam: 'JetBrains Mono',
      color: active ? '#2EE6D6' : 'rgba(255,255,255,0.45)' });
    emoji(e, x + 160, y + 76, 84);
    wrapFit(label, x + 228, y + 78, 600, 50, 36, { weight: 900, color: active ? '#fff' : 'rgba(255,255,255,0.75)' });
  });
}

// ------------------------------------------------- S6a: boarding pass
function ticketShape(x0, y0, w, h, ny, nr, r) {
  ctx.beginPath();
  ctx.moveTo(x0 + r, y0);
  ctx.lineTo(x0 + w - r, y0); ctx.arcTo(x0 + w, y0, x0 + w, y0 + r, r);
  ctx.lineTo(x0 + w, ny - nr); ctx.arc(x0 + w, ny, nr, -Math.PI / 2, Math.PI / 2, true);
  ctx.lineTo(x0 + w, y0 + h - r); ctx.arcTo(x0 + w, y0 + h, x0 + w - r, y0 + h, r);
  ctx.lineTo(x0 + r, y0 + h); ctx.arcTo(x0, y0 + h, x0, y0 + h - r, r);
  ctx.lineTo(x0, ny + nr); ctx.arc(x0, ny, nr, Math.PI / 2, -Math.PI / 2, true);
  ctx.lineTo(x0, y0 + r); ctx.arcTo(x0, y0, x0 + r, y0, r);
  ctx.closePath();
}

function marker(t, t0, x, y, w, h) {
  const k = eOut(prog(t, t0, 0.35));
  if (k <= 0) return;
  ctx.save();
  ctx.fillStyle = 'rgba(255,228,92,0.9)';
  rr(x - 10, y - h / 2, (w + 20) * k, h, 10);
  ctx.fill();
  ctx.restore();
}

function ticket(t) {
  const w = 840, h = 900, x0 = -420, y0 = -450, ny = 245, nr = 34;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 50; ctx.shadowOffsetY = 20;
  ticketShape(x0, y0, w, h, ny, nr, 36);
  ctx.fillStyle = '#F6F8FF'; ctx.fill();
  ctx.restore();
  ctx.save();
  ctx.beginPath(); ctx.roundRect(x0, y0, w, 150, [36, 36, 0, 0]);
  ctx.fillStyle = grad(x0, 0, x0 + w, 0, ['#4D7CFE', '#2EE6D6']); ctx.fill();
  ctx.restore();
  txt('BOARDING PASS', x0 + 50, y0 + 58, { size: 44, weight: 900, align: 'left', ls: 4 });
  txt('ПОСАДКОВИЙ ТАЛОН', x0 + 52, y0 + 108, { size: 28, weight: 700, color: 'rgba(255,255,255,0.92)', align: 'left', ls: 3 });
  emoji('✈️', x0 + w - 90, y0 + 75, 80);
  // route
  txt('ODS', x0 + 58, y0 + 245, { size: 104, weight: 900, color: '#0D1640', align: 'left' });
  txt('Одеса 🇺🇦', x0 + 62, y0 + 318, { size: 30, weight: 700, color: '#5A6488', align: 'left' });
  emoji('🌍', x0 + w - 110, y0 + 245, 100);
  txt('Весь світ', x0 + w - 58, y0 + 318, { size: 30, weight: 700, color: '#5A6488', align: 'right' });
  ctx.save();
  ctx.strokeStyle = '#B7C0DD'; ctx.lineWidth = 5; ctx.setLineDash([14, 12]);
  ctx.beginPath(); ctx.moveTo(x0 + 330, y0 + 245); ctx.lineTo(x0 + w - 190, y0 + 245); ctx.stroke();
  ctx.restore();
  emoji('✈️', lerp(x0 + 345, x0 + w - 205, (t * 0.35) % 1), y0 + 240, 50, { rot: 0.78 });
  // programme
  const lab = (s, x, y) => txt(s, x, y, { size: 24, weight: 800, color: '#8A93B5', align: 'left', ls: 2 });
  lab('ОСВІТНЯ ПРОГРАМА', x0 + 60, -62);
  const l1 = 'Менеджмент міжнародного', l2 = 'бізнесу';
  const ps = 48;
  marker(t, C.program, x0 + 60, -5, measure(l1, ps, 900), 62);
  marker(t, C.program + 0.25, x0 + 60, 55, measure(l2, ps, 900), 62);
  txt(l1, x0 + 60, -5, { size: ps, weight: 900, color: '#0D1640', align: 'left' });
  txt(l2, x0 + 60, 55, { size: ps, weight: 900, color: '#0D1640', align: 'left' });
  lab('УНІВЕРСИТЕТ', x0 + 60, 122);
  const uni = 'Одеська політехніка';
  marker(t, C.poly, x0 + 60, 175, measure(uni, ps, 900), 62);
  txt(uni, x0 + 60, 175, { size: ps, weight: 900, color: '#0D1640', align: 'left' });
  // perforation
  ctx.save();
  ctx.strokeStyle = '#C9CFE6'; ctx.lineWidth = 4; ctx.setLineDash([12, 12]);
  ctx.beginPath(); ctx.moveTo(x0 + nr + 10, ny); ctx.lineTo(x0 + w - nr - 10, ny); ctx.stroke();
  ctx.restore();
  // stub
  [['ПАСАЖИР', 'Ти 😉'], ['РЕЙС', 'Вступ-2027'], ['МІСЦЕ', '1 курс']].forEach(([a, b], i) => {
    const cx = x0 + 60 + i * 270;
    lab(a, cx, ny + 50);
    txt(b, cx, ny + 98, { size: 38, weight: 900, color: '#0D1640', align: 'left' });
  });
  ctx.fillStyle = '#0D1640';
  let bx = x0 + 60;
  for (let i = 0; bx < x0 + w - 60; i++) {
    const bw = 3 + Math.floor(rnd(i + 900) * 3) * 3;
    if (i % 2 === 0) ctx.fillRect(bx, ny + 140, bw, 50);
    bx += bw + 2;
  }
  // moving shine
  const sp = ((t - S.S6) * 0.6) % 1.6;
  ctx.save();
  ticketShape(x0, y0, w, h, ny, nr, 36); ctx.clip();
  const sx = lerp(x0 - 300, x0 + w + 300, sp);
  const g = ctx.createLinearGradient(sx - 120, 0, sx + 120, 0);
  g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.5, 'rgba(255,255,255,0.45)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g; ctx.fillRect(x0, y0, w, h);
  ctx.restore();
}

function sceneTicket(t) {
  bgReality(t, 1);
  chip('ТВІЙ КВИТОК У СВІТ ✈️', 540, 255, { bg: GOLD, fg: '#2A0E61', size: 44, rot: -0.03,
    scale: eBack(prog(t, S.S6 + 0.02, 0.3)), glow: 'rgba(255,200,80,0.6)' });
  const k = eBack(prog(t, S.S6 + 0.1, 0.6));
  tf(540, 840 + lerp(1400, 0, k), { rot: lerp(0.15, -0.02, k) }, () => ticket(t));
}

// ------------------------------------------------------ S6b: Odesa sea gates
function crane(x, base, s) {
  ctx.save();
  ctx.translate(x, base); ctx.scale(s, s);
  ctx.strokeStyle = '#0A0F2C'; ctx.fillStyle = '#0A0F2C'; ctx.lineWidth = 9; ctx.lineCap = 'square';
  ctx.beginPath();
  ctx.moveTo(-40, 0); ctx.lineTo(-30, -230); ctx.moveTo(40, 0); ctx.lineTo(30, -230);
  ctx.moveTo(-36, -120); ctx.lineTo(36, -120);
  ctx.moveTo(-90, -230); ctx.lineTo(230, -230);
  ctx.moveTo(-30, -230); ctx.lineTo(0, -300); ctx.lineTo(30, -230);
  ctx.moveTo(0, -300); ctx.lineTo(200, -232);
  ctx.stroke();
  ctx.fillRect(110, -228, 30, 22);
  ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(125, -206); ctx.lineTo(125, -120); ctx.stroke();
  ctx.fillRect(105, -125, 40, 22);
  ctx.restore();
}

function sceneSea(t) {
  const HZ = 1000;
  ctx.fillStyle = grad(0, 0, 0, HZ, ['#0B1640', '#2A2F86', '#7C4FA8', '#E0709A', '#FFB27A']);
  ctx.fillRect(0, 0, W, HZ);
  for (let i = 0; i < 40; i++) sparkle(rnd(i + 11) * W, rnd(i + 22) * 520, 3 + rnd(i) * 5, 0.4 + 0.4 * Math.sin(t * 2 + i));
  blob(540, HZ, 520, 'rgba(255,190,120,0.55)');
  ctx.fillStyle = grad(0, HZ, 0, H, ['#3A4C9A', '#142A66', '#06112E']);
  ctx.fillRect(0, HZ, W, H - HZ);
  for (let i = 0; i < 26; i++) {
    const y = HZ + 8 + i * i * 1.6;
    ctx.strokeStyle = `rgba(255,${190 - i * 3},${150 - i * 2},${0.32 - i * 0.01})`;
    ctx.lineWidth = 2 + i * 0.25;
    ctx.beginPath();
    for (let x = 0; x <= W; x += 12) {
      const yy = y + Math.sin(x * (0.02 - i * 0.0004) + t * (1.5 + i * 0.05) + i) * (2 + i * 0.5);
      x ? ctx.lineTo(x, yy) : ctx.moveTo(x, yy);
    }
    ctx.stroke();
  }
  // pier + cranes (left), lighthouse (right)
  ctx.fillStyle = '#0A0F2C';
  ctx.fillRect(0, HZ - 12, 300, 30);
  crane(70, HZ - 12, 0.8);
  crane(220, HZ - 12, 0.6);
  const lx = 960;
  ctx.fillStyle = '#0A0F2C'; ctx.fillRect(lx - 60, HZ - 14, 120, 30);
  ctx.beginPath(); ctx.moveTo(lx - 28, HZ - 14); ctx.lineTo(lx - 17, HZ - 220); ctx.lineTo(lx + 17, HZ - 220); ctx.lineTo(lx + 28, HZ - 14); ctx.closePath();
  ctx.fillStyle = '#F2F2F7'; ctx.fill();
  ctx.fillStyle = '#E43D4F';
  for (let k = 0; k < 3; k++) ctx.fillRect(lx - 26 + k * 3, HZ - 60 - k * 60, 52 - k * 6, 26);
  ctx.fillStyle = '#0A0F2C'; ctx.fillRect(lx - 24, HZ - 258, 48, 40);
  const ba = Math.sin(t * 1.4) * 0.9 + Math.PI;
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  const bg2 = ctx.createRadialGradient(lx, HZ - 238, 0, lx, HZ - 238, 700);
  bg2.addColorStop(0, 'rgba(255,240,180,0.55)'); bg2.addColorStop(1, 'rgba(255,240,180,0)');
  ctx.fillStyle = bg2;
  ctx.beginPath(); ctx.moveTo(lx, HZ - 238); ctx.arc(lx, HZ - 238, 700, ba - 0.12, ba + 0.12); ctx.closePath(); ctx.fill();
  ctx.restore();
  blob(lx, HZ - 238, 60, 'rgba(255,240,180,0.95)');
  emoji('🚢', lerp(420, 640, prog(t, S.S6b, 4.5)), HZ - 26, 64);

  // title
  const ko = eBack(prog(t, C.odesa - 0.08, 0.35));
  tf(540, 300, { scale: ko }, () => txt('ОДЕСА', 0, 0, { size: 130, weight: 900, shadow: 'rgba(255,150,120,0.8)', blur: 40, ls: 6 }));
  txt('морські ворота України ⚓', 540, 410, { size: 44, weight: 800, color: '#FFE2C2', alpha: eOut(prog(t, C.odesa + 0.25, 0.35)) });

  // the gate
  const gx0 = 290, gx1 = 790, gTop = 560, gBot = HZ;
  const open = eInOut(prog(t, C.gates - 0.1, 0.6));
  if (open > 0) {
    ctx.save();
    ctx.beginPath(); ctx.rect(gx0 + 50, gTop - 120, gx1 - gx0 - 100, gBot - gTop + 120); ctx.clip();
    blob(540, 780, 420 * (0.6 + 0.4 * open), `rgba(255,236,170,${0.95 * open})`);
    for (let i = 0; i < 10; i++) {
      const a = i * Math.PI / 5 + t * 0.8;
      ctx.fillStyle = `rgba(255,255,220,${0.18 * open})`;
      ctx.beginPath(); ctx.moveTo(540, 780); ctx.arc(540, 780, 600, a, a + 0.2); ctx.closePath(); ctx.fill();
    }
    ctx.restore();
    emoji('🌍', 540, 780, 190, { scale: eBack(prog(t, C.gates + 0.1, 0.45)) });
  }
  const doorW = (gx1 - gx0 - 100) / 2;
  [[gx0 + 50, 1], [gx1 - 50, -1]].forEach(([hx, dir]) => {
    const wv = doorW * (1 - 0.88 * open);
    ctx.save();
    ctx.fillStyle = grad(hx, 0, hx + dir * doorW, 0, ['#14205A', '#22337E']);
    const xa = dir > 0 ? hx : hx - wv;
    ctx.fillRect(xa, gTop, wv, gBot - gTop);
    ctx.strokeStyle = '#FFC24B'; ctx.lineWidth = 5;
    ctx.strokeRect(xa + 14, gTop + 20, Math.max(0, wv - 28), (gBot - gTop) / 2 - 30);
    ctx.strokeRect(xa + 14, gTop + (gBot - gTop) / 2 + 10, Math.max(0, wv - 28), (gBot - gTop) / 2 - 30);
    ctx.restore();
    if (open < 0.3) emoji('⚓', hx + dir * doorW / 2, gTop + (gBot - gTop) / 2 - 10, 60, { alpha: 1 - open / 0.3 });
  });
  ctx.fillStyle = '#0E1440';
  ctx.fillRect(gx0, gTop - 20, 50, gBot - gTop + 20);
  ctx.fillRect(gx1 - 50, gTop - 20, 50, gBot - gTop + 20);
  ctx.strokeStyle = '#FFC24B'; ctx.lineWidth = 4;
  ctx.strokeRect(gx0 + 8, gTop - 12, 34, gBot - gTop + 4);
  ctx.strokeRect(gx1 - 42, gTop - 12, 34, gBot - gTop + 4);
  ctx.save();
  ctx.beginPath(); ctx.roundRect(gx0 - 20, gTop - 110, gx1 - gx0 + 40, 100, 26);
  ctx.fillStyle = '#0E1440'; ctx.fill(); ctx.strokeStyle = '#FFC24B'; ctx.lineWidth = 5; ctx.stroke();
  ctx.restore();
  txtFit('ОДЕСЬКА ПОЛІТЕХНІКА', 540, gTop - 58, gx1 - gx0 - 10, { size: 36, weight: 900, color: '#FFC24B', ls: 2 });
  chip('ТВОЇ ВОРОТА У СВІТ 🌍', 540, 1130, { bg: GOLD, fg: '#2A0E61', size: 46, rot: -0.03,
    scale: eBack(prog(t, C.gates + 0.2, 0.35)), glow: 'rgba(255,200,80,0.8)' });
}

// --------------------------------------------------------- S7: finale
function confetti(t, t0) {
  const d = t - t0;
  if (d < 0) return;
  const cols = ['#FFE45C', '#2EE6D6', '#FF5E8A', '#4D7CFE', '#A050FF', '#2EE68A'];
  for (let i = 0; i < 150; i++) {
    const a = -Math.PI / 2 + (rnd(i) - 0.5) * 2.6;
    const sp = 900 + rnd(i + 3) * 1500;
    const x = 540 + Math.cos(a) * sp * d;
    const y = 720 + Math.sin(a) * sp * d + 0.5 * 2200 * d * d;
    if (y > H + 40) continue;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(rnd(i + 5) * 6 + d * (4 + rnd(i + 6) * 8));
    ctx.scale(1, Math.cos(d * (6 + rnd(i + 9) * 6)));
    ctx.fillStyle = cols[i % cols.length];
    ctx.fillRect(-11, -6, 22, 12);
    ctx.restore();
  }
}

function sceneFinal(t) {
  const tE = C.enroll - 0.05;
  if (t < tE) {
    bgReality(t);
    const ys = lerp(960, 430, eInOut(prog(t, C.reality - 0.1, 0.6)));
    const yL = ys + 130, yR = ys - 130;
    ctx.save();
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(W, 0); ctx.lineTo(W, yR); ctx.lineTo(0, yL); ctx.closePath();
    ctx.clip();
    ctx.fillStyle = grad(0, 0, 0, 1000, ['#7A1E86', '#D23F86', '#FF7A59', '#FFC56B']);
    ctx.fillRect(0, 0, W, H);
    for (let i = 0; i < 16; i++) sparkle(rnd(i) * W, 150 + rnd(i + 99) * 800, 10 + rnd(i + 7) * 14, Math.sin(t * 3 + i * 1.7));
    const ga = clamp((ys - 520) / 300);
    emoji('😎', 540, ys - 260, 200, { alpha: ga, scale: eBack(prog(t, S.S7 + 0.1, 0.35)) });
    ctx.restore();
    ctx.save();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 10; ctx.shadowColor = 'rgba(255,255,255,0.9)'; ctx.shadowBlur = 30;
    ctx.beginPath(); ctx.moveTo(-10, yL + 3); ctx.lineTo(W + 10, yR - 3); ctx.stroke();
    ctx.restore();
    chip('ОЧІКУВАННЯ', 540, Math.max(255, ys - 470), { bg: GOLD, fg: '#3A1060', size: 42, rot: -0.07,
      scale: eBack(prog(t, S.S7 + 0.05, 0.3)) * lerp(1, 0.8, 1 - clamp((ys - 430) / 530)) });
    chip('РЕАЛЬНІСТЬ 💼', 540, ys + 230, { bg: CYAN, fg: '#06102A', size: 52, rot: -0.04,
      scale: eBack(prog(t, S.S7 + 0.15, 0.3)) * lerp(1, 1.15, 1 - clamp((ys - 430) / 530)), glow: 'rgba(46,230,214,0.7)' });
    ['💼', '🌍', '🤝', '📈', '🚀'].forEach((e, i) => {
      emoji(e, 140 + i * 200, ys + 420 + Math.sin(t * 4 + i) * 8, 110, { scale: eBack(prog(t, C.reality + 0.2 + i * 0.07, 0.3)) });
    });
    tf(540, ys + 600, { scale: eBack(prog(t, C.better - 0.05, 0.3)), rot: -0.04 }, () =>
      txt('ЦІКАВІША! 🔥', 0, 0, { size: 90, weight: 900, color: '#FFE45C', stroke: '#2A0E61', sw: 14 }));
    return;
  }
  bgReality(t, 1);
  blob(540, 720, 600, 'rgba(255,194,75,0.25)');
  emoji('😉', 540, 470 + Math.sin(t * 3) * 8, 190, { scale: eBack(prog(t, tE, 0.4)) });
  const pul = 1 + 0.04 * Math.sin((t - tE) * 8);
  tf(540, 720, { scale: eBack(prog(t, tE + 0.05, 0.35)) * pul, rot: -0.03 }, () => {
    const bw = 640, bh = 150;
    ctx.save();
    ctx.shadowColor = 'rgba(255,94,138,0.8)'; ctx.shadowBlur = 50;
    rr(-bw / 2, -bh / 2, bw, bh, bh / 2);
    ctx.fillStyle = grad(-bw / 2, 0, bw / 2, 0, ['#FFE45C', '#FF8A5B', '#FF5E8A']); ctx.fill();
    ctx.restore();
    txt('ВСТУПАЙ! 🚀', 0, 4, { size: 74, weight: 900, color: '#2A0E61' });
  });
  const ki = eOut(prog(t, tE + 0.25, 0.4));
  ctx.save();
  ctx.globalAlpha = ki;
  ctx.translate(0, lerp(60, 0, ki));
  txt('Освітня програма', 540, 885, { size: 38, weight: 700, color: '#9FB3FF' });
  txtFit('«Менеджмент', 540, 955, 900, { size: 66, weight: 900 });
  txtFit('міжнародного бізнесу»', 540, 1030, 900, { size: 66, weight: 900 });
  txt('Одеська політехніка', 540, 1120, { size: 54, weight: 900, color: '#FFC24B', shadow: 'rgba(255,194,75,0.6)', blur: 20 });
  txt('#вступ2027  ·  International Business: My Future', 540, 1215, { size: 30, weight: 700, color: 'rgba(255,255,255,0.75)' });
  ctx.restore();
  confetti(t, tE);
  if (t < tE + 0.25) {
    ctx.fillStyle = `rgba(255,255,255,${0.9 * (1 - (t - tE) / 0.25)})`;
    ctx.fillRect(0, 0, W, H);
  }
}

// ------------------------------------------------------- global overlays
const CUTS = [S.S3, S.S3b, S.S4, S.S4b, S.S5, S.S6, S.S6b, S.S7];
function wipe(t) {
  const d = 0.2;
  for (const c of CUTS) {
    if (t <= c - d || t >= c + d) continue;
    const q = (t - (c - d)) / (2 * d);
    const x = lerp(-2.2 * W, 2.2 * W, eInOut(q));
    ctx.save();
    ctx.translate(x + W / 2, H / 2);
    ctx.rotate(-0.35);
    const bw = 2.2 * W;
    const g = ctx.createLinearGradient(-bw / 2, 0, bw / 2, 0);
    g.addColorStop(0, 'rgba(46,230,214,0)');
    g.addColorStop(0.1, '#2EE6D6');
    g.addColorStop(0.5, '#4D7CFE');
    g.addColorStop(0.9, '#A050FF');
    g.addColorStop(1, 'rgba(160,80,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(-bw / 2, -H * 1.3, bw, H * 2.6);
    ctx.restore();
  }
}

const IMPACTS = [[S.S2, 22], [C.deal, 26], [S.S4, 14], [C.gates, 12], [C.enroll, 24]];
function shake(t) {
  let dx = 0, dy = 0;
  for (const [ti, a] of IMPACTS) {
    const d = t - ti;
    if (d >= 0 && d < 0.35) {
      const amp = a * Math.exp(-d / 0.08);
      dx += amp * Math.sin(d * 90);
      dy += amp * Math.cos(d * 77);
    }
  }
  return [dx, dy];
}

function captions(t) {
  const c = TL.captions.find(c => t >= c.s && t < c.e);
  if (!c) return;
  const size = 66, maxW = 880, Y = 1400;
  ctx.save();
  ctx.font = font(size, 900);
  const space = ctx.measureText(' ').width;
  const ws = c.words.map(w => ({ ...w, width: ctx.measureText(w.w).width }));
  const lines = [[]], lw = [0];
  for (const w of ws) {
    const cur = lines[lines.length - 1];
    const add = (cur.length ? space : 0) + w.width;
    if (lw[lw.length - 1] + add > maxW && cur.length) { lines.push([w]); lw.push(w.width); }
    else { cur.push(w); lw[lw.length - 1] += add; }
  }
  const sc = lerp(0.8, 1, eBack(prog(t, c.s, 0.12)));
  const lh = size * 1.15, y0 = Y - (lines.length - 1) * lh / 2;
  ctx.translate(540, Y); ctx.scale(sc, sc); ctx.translate(-540, -Y);
  ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
  lines.forEach((ln, li) => {
    let x = 540 - lw[li] / 2;
    const y = y0 + li * lh;
    for (const w of ln) {
      const cur = t >= w.s - 0.02 && t < w.e + 0.05;
      ctx.lineWidth = 14; ctx.strokeStyle = 'rgba(8,8,24,0.95)';
      ctx.strokeText(w.w, x, y);
      ctx.fillStyle = cur ? '#FFE45C' : '#FFFFFF';
      ctx.fillText(w.w, x, y);
      x += w.width + space;
    }
  });
  ctx.restore();
}

function draw(t) {
  ctx = mainCtx;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalAlpha = 1;
  ctx.filter = 'none';
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, W, H);
  const [dx, dy] = shake(t);
  ctx.save();
  if (dx || dy) { ctx.translate(W / 2 + dx, H / 2 + dy); ctx.scale(1.05, 1.05); ctx.translate(-W / 2, -H / 2); }
  if (t < S.scratch) sceneExpect(t);
  else if (t < S.S2) sceneFreeze(t);
  else if (t < S.S3) sceneZones(t);
  else if (t < S.S3b) sceneBoring(t);
  else if (t < S.S4) sceneQuest(t);
  else if (t < S.S4b) sceneAlarm(t);
  else if (t < S.S5) sceneAI(t);
  else if (t < S.S6) sceneCareers(t);
  else if (t < S.S6b) sceneTicket(t);
  else if (t < S.S7) sceneSea(t);
  else sceneFinal(t);
  ctx.restore();
  vignette();
  wipe(t);
  if (t >= S.S2 && t < S.S2 + 0.2) {
    ctx.fillStyle = `rgba(255,255,255,${0.8 * (1 - (t - S.S2) / 0.2)})`;
    ctx.fillRect(0, 0, W, H);
  }
  captions(t);
}
window.draw = draw;
