// Gob, the pet: a canvas port of Gobbl/Pet/GobView.swift, shared by every page.
// Three computers (classic, retro = compact, candy) with a phosphor face on the
// screen. "work" fills the screen with Matrix rain, "think" ponders, "type"
// hops with each key press. One animation loop draws every visible pet.
(() => {
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const STATIC = document.documentElement.classList.contains("static");
const hsl = (h, s, l) => `hsl(${h * 360},${s}%,${l}%)`;
// Mirrors GobblCore/Mascot/PetGenome.swift.
const SPECIES = [["Mochi",.93,20],["Sprout",.30,18],["Ember",.04,16],["Frost",.55,16],["Bubble",.48,14],["Sunny",.13,10],["Plum",.78,5],["Cosmo",.68,1]];
const rarity = w => w >= 14 ? "common" : w >= 10 ? "uncommon" : w >= 5 ? "rare" : "legendary";
const keyTimes = [];
const GLYPHS = "01アイウエオカキクケコサシスセソタチツテトﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ";

function rr(ctx, x, y, w, h, r, fill, stroke) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); if (fill) ctx.fill(); if (stroke) ctx.stroke(); }
function palette(o) {
  const h = o.hue ?? .3;
  const d = { classic: [hsl(h, 30, 88), hsl(h, 22, 70)], retro: [hsl(h, 35, 93), hsl(h, 22, 78)], candy: [hsl(h, 100, 72), hsl(h, 80, 45)] }[o.char || "retro"];
  return { light: o.top || d[0], dark: o.bottom || d[1] };
}
function grad(ctx, y0, y1, a, b) { const g = ctx.createLinearGradient(0, y0, 0, y1); g.addColorStop(0, a); g.addColorStop(1, b); return g; }

// A shipping box that shakes, then pops its flaps (k: 0 to 1).
function drawBox(ctx, s, t, k) {
  ctx.clearRect(0, 0, s, s);
  const w = s * .62, h = s * .4, x = (s - w) / 2, y = s * .5, f = Math.max(0, (k - .7) / .3);
  const shake = k < .7 ? Math.sin(t * 50) * .05 * (.3 + k) : 0;
  ctx.save(); ctx.translate(s / 2, y + h); ctx.rotate(shake); ctx.translate(-s / 2, -(y + h));
  ctx.fillStyle = "#a8743f";
  for (const side of [-1, 1]) {
    const outer = side < 0 ? x : x + w, inner = x + w / 2, lift = h * .55 * f, flare = w * .14 * f * side;
    ctx.beginPath(); ctx.moveTo(outer, y); ctx.lineTo(inner, y); ctx.lineTo(inner + flare * .3, y - lift - 3); ctx.lineTo(outer + flare, y - lift * .9 - 3); ctx.closePath(); ctx.fill();
  }
  ctx.fillStyle = grad(ctx, y, y + h, "#ddaa6a", "#c8914f"); rr(ctx, x, y, w, h, s * .015, true);
  if (f < .05) { ctx.fillStyle = "rgba(233,207,148,.95)"; ctx.fillRect(x + w / 2 - s * .02, y - 2, s * .04, h * .42); }
  ctx.fillStyle = "rgba(255,255,255,.92)"; rr(ctx, x + w * .1, y + h * .46, w * .42, h * .36, 4, true);
  ctx.fillStyle = "#2a2d33"; ctx.font = `800 ${s * .05}px ui-rounded,-apple-system,sans-serif`; ctx.textAlign = "center"; ctx.fillText("gobbl", x + w * .31, y + h * .67);
  ctx.save(); ctx.translate(x + w * .78, y + h * .66); ctx.rotate(-.2); ctx.strokeStyle = ctx.fillStyle = "rgba(210,70,60,.9)"; ctx.lineWidth = 2;
  rr(ctx, -s * .09, -s * .03, s * .18, s * .06, 3, false, true); ctx.font = `900 ${s * .03}px sans-serif`; ctx.fillText("FRAGILE", 0, s * .011); ctx.restore();
  ctx.textAlign = "start";
  ctx.restore();
}

function drawPet(ctx, s, t, o) {
  if (o.boxUntil && performance.now() < o.boxUntil) { drawBox(ctx, s, t, 1 - (o.boxUntil - performance.now()) / 1200); return; }
  ctx.clearRect(0, 0, s, s);
  // Leave headroom for a hat so it isn't cut off at the canvas top.
  if (o.hat) { ctx.save(); ctx.translate(s / 2, s); ctx.scale(.8, .8); ctx.translate(-s / 2, -s); drawBody(ctx, s, t, o); ctx.restore(); }
  else drawBody(ctx, s, t, o);
}
function drawBody(ctx, s, t, o) {
  const m = o.mood || "idle";
  const now = performance.now();
  const ages = keyTimes.map(k => (now - k) / 1000).filter(a => a < 2);
  const pulse = m === "type" && ages.length ? Math.max(0, 1 - ages[ages.length - 1] / .15) : 0;
  const heat = ages.length / 14;
  let sq = Math.sin(t * 2.2) * .012, dx = 0, dy = 0, tilt = 0;
  if (m === "dance") { sq = Math.sin(t * 8) * .035; dx = Math.sin(t * 4) * s * .05; tilt = Math.sin(t * 4) * .12; }
  if (m === "eating") sq = Math.abs(Math.sin(t * 14)) * .05;
  if (m === "party") { dy = -Math.abs(Math.sin(t * 7)) * s * .1; sq = Math.cos(t * 14) * .025; }
  if (m === "love") sq = Math.sin(t * 5) * .02;
  if (m === "alert") dx = Math.sin(t * 40) * s * .012;
  if (m === "work") dy = -Math.abs(Math.sin(t * 12)) * s * .01;
  if (m === "think") tilt = Math.sin(t * 1.4) * .05;
  if (m === "type") { dy = -pulse * s * .035; sq = pulse * .03; tilt = (Math.min(1, heat) - .5) * .06; }
  if (o.open) sq = -.035 + Math.sin(t * 9) * .01;
  const bx = s / 2 + dx, by = s * .95 + dy;
  ctx.save();
  ctx.translate(bx, by); ctx.rotate(tilt); ctx.translate(-bx, -by);
  const p = palette(o), ch = o.char || "retro";
  const parts = ch === "classic" ? classic(ctx, s, t, o, m, sq, bx, by, p) : ch === "candy" ? candy(ctx, s, t, o, m, sq, bx, by, p) : compact(ctx, s, t, o, m, sq, bx, by, p);
  screen(ctx, s, t, o, m, parts.screen);
  if (o.hat) hat(ctx, s, t, o.hat, parts.body);
  if (o.shiny) for (let i = 0; i < 3; i++) { const q = (t * .7 + i / 3) % 1, a = i * 2.1 + .6; ctx.fillStyle = "#fff"; sparkle(ctx, parts.body.x + parts.body.w / 2 + Math.cos(a) * parts.body.w * .6, parts.body.y + parts.body.h / 2 + Math.sin(a) * parts.body.h * .62, s * .05 * Math.sin(q * Math.PI) + .5); }
  ctx.restore();
  if (s > 60) extras(ctx, s, t, m, parts.body, ages, heat);
}

// A four-point glint for limited editions (drawn, not a text glyph).
function sparkle(ctx, x, y, r) { ctx.beginPath(); ctx.moveTo(x, y - r); ctx.quadraticCurveTo(x, y, x + r, y); ctx.quadraticCurveTo(x, y, x, y + r); ctx.quadraticCurveTo(x, y, x - r, y); ctx.quadraticCurveTo(x, y, x, y - r); ctx.fill(); }
function disk(ctx, t, o, slot, size) {
  const q = o.open ? 0 : (t * 1.4) % 1;
  ctx.fillStyle = "#3e6be0"; rr(ctx, slot.x + slot.w / 2 - size / 2, slot.y + slot.h / 2 - size * (1 - q), size, size * (1 - q), size * .06, true);
}
function compact(ctx, s, t, o, m, sq, bx, by, p) {
  const k = sq, w = s * .7 * (1 + k), h = s * .8 * (1 - k), x = bx - w / 2, y = by - s * .02 - h;
  ctx.fillStyle = p.dark; for (const side of [-1, 1]) rr(ctx, bx + side * w * .3 - w * .1, y + h - s * .01, w * .2, s * .04, s * .02, true);
  ctx.fillStyle = grad(ctx, y, y + h, p.light, p.dark); rr(ctx, x, y, w, h, w * .13, true);
  ctx.strokeStyle = "rgba(255,255,255,.35)"; ctx.lineWidth = Math.max(.5, s * .008); rr(ctx, x, y, w, h, w * .13, false, true);
  const sc = { x: x + w * .13, y: y + h * .09, w: w * .74, h: h * .52 };
  ctx.fillStyle = "rgba(0,0,0,.2)"; rr(ctx, sc.x - w * .035, sc.y - w * .035, sc.w + w * .07, sc.h + w * .07, w * .1, true);
  const slot = { x: bx - w * .02, y: y + h * .76, w: w * .34, h: Math.max(1.5, h * .035) };
  if (m === "eating" || o.open) disk(ctx, t, o, slot, w * .22);
  ctx.fillStyle = "rgba(0,0,0,.6)"; rr(ctx, slot.x, slot.y, slot.w, slot.h, slot.h / 2, true);
  const busy = ["eating", "work", "think"].includes(m);
  ctx.fillStyle = busy && Math.sin(t * 20) > -.3 ? "#a6f25c" : "rgba(0,0,0,.25)"; rr(ctx, slot.x + slot.w - w * .07, slot.y + slot.h + h * .035, w * .05, Math.max(1, h * .022), 2, true);
  ctx.fillStyle = "rgba(0,0,0,.18)"; for (let i = 0; i < 3; i++) rr(ctx, x + w * .13 + i * w * .05, slot.y - h * .01, Math.max(1, w * .018), h * .08, 1, true);
  return { body: { x, y, w, h }, screen: sc };
}
function classic(ctx, s, t, o, m, sq, bx, by, p) {
  const kw = s * .92 * (1 + sq), kh = s * .22 * (1 - sq), kx = bx - kw / 2, ky = by - kh;
  ctx.fillStyle = grad(ctx, ky, ky + kh, p.light, p.dark);
  ctx.beginPath(); ctx.moveTo(kx + kw * .07, ky); ctx.lineTo(kx + kw * .93, ky); ctx.lineTo(kx + kw, ky + kh * .8); ctx.quadraticCurveTo(kx + kw, ky + kh, kx + kw * .96, ky + kh);
  ctx.lineTo(kx + kw * .04, ky + kh); ctx.quadraticCurveTo(kx, ky + kh, kx, ky + kh * .8); ctx.closePath(); ctx.fill();
  ctx.fillStyle = "rgba(0,0,0,.2)";
  for (let r = 0; r < (s > 60 ? 3 : 2); r++) {
    const yy = ky + kh * (.25 + r * .22), inset = kw * (.13 - r * .015);
    if (s > 60) { const n = 10, gap = kw * .012, keyW = (kw - 2 * inset - (n - 1) * gap) / n; for (let i = 0; i < n; i++) rr(ctx, kx + inset + i * (keyW + gap), yy, keyW, kh * .14, keyW * .2, true); }
    else ctx.fillRect(kx + inset, yy, kw - 2 * inset, Math.max(1, kh * .12));
  }
  const mw = s * .66 * (1 + sq), mh = s * .56 * (1 - sq), mx = bx - mw / 2, my = ky - mh + s * .015;
  ctx.fillStyle = grad(ctx, my, my + mh, p.light, p.dark); rr(ctx, mx, my, mw, mh, mw * .07, true);
  ctx.strokeStyle = "rgba(255,255,255,.3)"; ctx.lineWidth = Math.max(.5, s * .008); rr(ctx, mx, my, mw, mh, mw * .07, false, true);
  const sc = { x: mx + mw * .1, y: my + mh * .1, w: mw * .8, h: mh * .7 };
  ctx.fillStyle = "rgba(0,0,0,.2)"; rr(ctx, sc.x - mw * .03, sc.y - mw * .03, sc.w + mw * .06, sc.h + mw * .06, mw * .06, true);
  const slot = { x: kx + kw * .7, y: ky + kh * .06, w: kw * .18, h: Math.max(1.2, kh * .08) };
  if (m === "eating" || o.open) disk(ctx, t, o, slot, kw * .12);
  ctx.fillStyle = "rgba(0,0,0,.55)"; rr(ctx, slot.x, slot.y, slot.w, slot.h, slot.h / 2, true);
  return { body: { x: mx, y: my, w: mw, h: mh }, screen: sc };
}
function candy(ctx, s, t, o, m, sq, bx, by, p) {
  const w = s * .8 * (1 + sq), h = s * .76 * (1 - sq), x = bx - w / 2, y = by - s * .05 - h, r = w * .2;
  ctx.fillStyle = p.dark; ctx.globalAlpha = .85; ctx.beginPath(); ctx.ellipse(bx, by - s * .035, w * .24, s * .035, 0, 0, 7); ctx.fill(); ctx.globalAlpha = 1;
  const shell = new Path2D();
  shell.moveTo(x + r, y); shell.lineTo(x + w - r, y); shell.quadraticCurveTo(x + w, y, x + w, y + r);
  shell.lineTo(x + w - w * .02, y + h * .7); shell.quadraticCurveTo(x + w - w * .06, y + h, bx, y + h);
  shell.quadraticCurveTo(x + w * .06, y + h, x + w * .02, y + h * .7); shell.lineTo(x, y + r); shell.quadraticCurveTo(x, y, x + r, y); shell.closePath();
  ctx.fillStyle = grad(ctx, y, y + h, p.light, p.dark); ctx.fill(shell);
  ctx.save(); ctx.clip(shell);
  if (s > 60) { ctx.fillStyle = "rgba(255,255,255,.13)"; for (let i = 0; i < 9; i++) ctx.fillRect(x + w * (.08 + i * .105), y + h * .72, w * .035, h * .3); }
  ctx.fillStyle = "rgba(255,255,255,.16)"; ctx.beginPath(); ctx.ellipse(x + w * .35, y + h * .02, w * .45, h * .27, 0, 0, 7); ctx.fill();
  ctx.restore();
  ctx.strokeStyle = "rgba(255,255,255,.45)"; ctx.lineWidth = Math.max(.5, s * .009); ctx.stroke(shell);
  const sc = { x: x + w * .15, y: y + h * .11, w: w * .7, h: h * .5 };
  ctx.strokeStyle = "rgba(255,255,255,.55)"; ctx.lineWidth = Math.max(1, s * .02); rr(ctx, sc.x - w * .025, sc.y - w * .025, sc.w + w * .05, sc.h + w * .05, w * .11, false, true);
  const slot = { x: bx - w * .16, y: y + h * .72, w: w * .32, h: Math.max(1.5, h * .03) };
  if (m === "eating" || o.open) { const q = o.open ? 0 : (t * 1.4) % 1, d = w * .24; ctx.fillStyle = "#e9f4ff"; ctx.beginPath(); ctx.ellipse(bx, slot.y - d * (1 - q) / 2, d / 2, d * (1 - q) / 2, 0, 0, 7); ctx.fill(); }
  ctx.fillStyle = "rgba(0,0,0,.45)"; rr(ctx, slot.x, slot.y, slot.w, slot.h, slot.h / 2, true);
  if (s > 60) { ctx.fillStyle = "rgba(0,0,0,.3)"; for (const side of [-1, 1]) for (let rw = 0; rw < 2; rw++) for (let c = 0; c < 3; c++) { ctx.beginPath(); ctx.arc(bx + side * w * (.27 + c * .035), slot.y - h * .03 + rw * h * .05, s * .006, 0, 7); ctx.fill(); } }
  return { body: { x, y, w, h }, screen: sc };
}

function screen(ctx, s, t, o, m, sc) {
  const glass = new Path2D(); glass.roundRect(sc.x, sc.y, sc.w, sc.h, sc.w * .1);
  const cg = ctx.createRadialGradient(sc.x + sc.w / 2, sc.y + sc.h / 2, 0, sc.x + sc.w / 2, sc.y + sc.h / 2, sc.w * .7);
  cg.addColorStop(0, "#1f3a28"); cg.addColorStop(1, "#0a120d"); ctx.fillStyle = cg; ctx.fill(glass);
  const ink = o.glow || "#a6f25c";
  const f = { cx: sc.x + sc.w / 2, ey: sc.y + sc.h * .4, dx: sc.w * .2, r: sc.w * .075, my: sc.y + sc.h * .73, w: sc.w, h: sc.h };
  const lw = Math.max(1.2, s * .03);
  if (o.text != null) { // boot text or typed characters on the phosphor screen
    ctx.save(); ctx.clip(glass); ctx.fillStyle = ink; if (s > 60) { ctx.shadowColor = ink; ctx.shadowBlur = s * .03; }
    const fs = sc.h * (o.text.length > 4 ? .2 : .36);
    ctx.font = `700 ${fs}px ui-monospace,Menlo,monospace`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    const txt = o.text.slice(-10) + (Math.floor(t * 2.5) % 2 ? "_" : " ");
    ctx.fillText(txt, sc.x + sc.w / 2, sc.y + sc.h / 2); ctx.restore(); ctx.textAlign = "start"; ctx.textBaseline = "alphabetic";
  } else if (m === "work") {
    ctx.save(); ctx.clip(glass); matrix(ctx, s, t, sc, ink); ctx.restore();
    eyes(ctx, s, t, o, m, f, lw, "rgba(255,255,255,.92)");
  } else {
    ctx.save(); if (s > 60) { ctx.shadowColor = ink; ctx.shadowBlur = s * .04; }
    eyes(ctx, s, t, o, m, f, lw, ink); mouth(ctx, s, t, o, m, f, lw, ink); ctx.restore();
    ctx.fillStyle = "rgba(255,111,165,.3)"; for (const side of [-1, 1]) rr(ctx, f.cx + side * f.dx * 1.6 - f.r, f.ey + f.r * 1.3, f.r * 2, f.r * .8, f.r * .3, true);
    if (m === "think") for (let i = 0; i < 3; i++) { ctx.fillStyle = ink; ctx.globalAlpha = Math.floor(t * 3) % 3 === i ? 1 : .3; const d = Math.max(1.2, sc.w * .05); ctx.beginPath(); ctx.arc(sc.x + sc.w * .7 + i * d * 1.6 + d / 2, sc.y + sc.h * .84 + d / 2, d / 2, 0, 7); ctx.fill(); ctx.globalAlpha = 1; }
  }
  if (s > 60) { ctx.fillStyle = "rgba(0,0,0,.22)"; for (let y = sc.y + s * .01; y < sc.y + sc.h - s * .005; y += s * .018) ctx.fillRect(sc.x + sc.w * .03, y, sc.w * .94, Math.max(.5, s * .004)); }
  if (o.scan != null) { // the CRT line of a booting screen (scan: 0 to 1)
    const y = sc.y + sc.h * o.scan; ctx.save(); ctx.clip(glass);
    ctx.fillStyle = "rgba(166,242,92,.18)"; ctx.fillRect(sc.x, sc.y, sc.w, y - sc.y);
    ctx.fillStyle = "#eaffd6"; ctx.shadowColor = "#a6f25c"; ctx.shadowBlur = s * .05; ctx.fillRect(sc.x, y - s * .004, sc.w, Math.max(1, s * .008)); ctx.restore();
  }
  ctx.fillStyle = "rgba(255,255,255,.07)"; ctx.beginPath(); ctx.ellipse(sc.x + sc.w * .23, sc.y + sc.h * .13, sc.w * .15, sc.h * .07, 0, 0, 7); ctx.fill();
}
function matrix(ctx, s, t, sc, ink) {
  const cell = Math.max(2.4, s * .045), cols = Math.max(4, Math.floor(sc.w / cell)), rows = Math.floor(sc.h / cell) + 1, colW = sc.w / cols;
  ctx.font = `700 ${cell * .95}px ui-monospace,Menlo,monospace`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
  for (let c = 0; c < cols; c++) {
    const speed = 4 + (c * 7) % 6, offset = (c * 37) % 97, trail = 4 + (c * 5) % 5;
    const head = Math.floor((t * speed + offset) % (rows + trail)), x = sc.x + (c + .5) * colW;
    for (let k = 0; k < trail; k++) {
      const r = head - k; if (r < 0 || r >= rows) continue;
      const y = sc.y + (r + .5) * cell;
      ctx.fillStyle = k === 0 ? "rgba(255,255,255,.95)" : ink; ctx.globalAlpha = k === 0 ? 1 : .85 * (1 - k / trail);
      if (s > 60) ctx.fillText(GLYPHS[(c * 131 + r * 17 + Math.floor(t * 8)) % GLYPHS.length], x, y);
      else ctx.fillRect(x - cell * .18, y - cell * .32, cell * .36, cell * .64);
    }
  }
  ctx.globalAlpha = 1; ctx.textAlign = "start"; ctx.textBaseline = "alphabetic";
}
function heartPath(ctx, x, y, size) { const s = size / 2; ctx.beginPath(); ctx.moveTo(x, y + s * .8); ctx.bezierCurveTo(x - s * .4, y + s * .5, x - s, y + s * .2, x - s, y - s * .2); ctx.arc(x - s * .5, y - s * .25, s * .5, Math.PI, 0); ctx.arc(x + s * .5, y - s * .25, s * .5, Math.PI, 0); ctx.bezierCurveTo(x + s, y + s * .2, x + s * .4, y + s * .5, x, y + s * .8); ctx.fill(); }
function eyes(ctx, s, t, o, m, f, lw, col) {
  const blink = !STATIC && (t % 4.3) < .13, r = f.r;
  ctx.strokeStyle = ctx.fillStyle = col; ctx.lineWidth = lw; ctx.lineCap = "round";
  for (const side of [-1, 1]) {
    const ex = f.cx + side * f.dx, ey = f.ey;
    if (m === "party" || m === "dance" || m === "happy") { ctx.beginPath(); ctx.moveTo(ex - r, ey + r * .3); ctx.quadraticCurveTo(ex, ey - r * 1.2, ex + r, ey + r * .3); ctx.stroke(); }
    else if (m === "love") { ctx.fillStyle = "#ff6fa5"; heartPath(ctx, ex, ey, r * 2.3); ctx.fillStyle = col; }
    else if (m === "sleep") { ctx.beginPath(); ctx.moveTo(ex - r, ey); ctx.quadraticCurveTo(ex, ey + r * .9, ex + r, ey); ctx.stroke(); }
    else if (blink && !o.open && m !== "think") { ctx.beginPath(); ctx.moveTo(ex - r, ey); ctx.lineTo(ex + r, ey); ctx.stroke(); }
    else {
      const big = (o.open || m === "alert" || m === "curious") ? 1.25 : 1, lid = m === "work" ? .5 : m === "think" ? .85 : 1;
      const w = r * 1.5 * big, h = r * 2 * big * lid;
      let px = ex + Math.max(-1, Math.min(1, o.look || 0)) * r * .45, py = ey + Math.max(-1, Math.min(1, o.lookY || 0)) * r * .35;
      if (m === "work") { px = ex + Math.sin(t * 5) * r * .3; py = ey + r * .35; }
      if (m === "type") { px = ex + Math.sin(t * 7) * r * .2; py = ey + r * .35; }
      if (m === "think") { px = ex + r * .45; py = ey - r * .4; }
      rr(ctx, px - w / 2, py - h / 2, w, h, w * .25, true);
      if (m === "think" && side > 0) { ctx.beginPath(); ctx.moveTo(ex - r * .9, ey - r * 1.55); ctx.lineTo(ex + r * .9, ey - r * 2.05); ctx.stroke(); }
    }
  }
}
function mouth(ctx, s, t, o, m, f, lw, ink) {
  const cx = f.cx, my = f.my;
  ctx.strokeStyle = ctx.fillStyle = ink; ctx.lineWidth = lw;
  if (m === "eating" || o.open) { const w = f.w * (o.open ? .32 : .28), h = o.open ? f.h * .24 : f.h * (.06 + Math.abs(Math.sin(t * 14)) * .16); ctx.beginPath(); ctx.ellipse(cx, my, w / 2, h / 2, 0, 0, 7); ctx.fill(); }
  else if (m === "alert") { ctx.beginPath(); ctx.arc(cx, my, s * .035, 0, 7); ctx.fill(); }
  else if (m === "think") { ctx.beginPath(); ctx.moveTo(cx - f.w * .05, my + f.h * .02); ctx.lineTo(cx + f.w * .07, my - f.h * .03); ctx.stroke(); }
  else if (m === "sleep") { ctx.beginPath(); ctx.moveTo(cx - f.w * .05, my); ctx.lineTo(cx + f.w * .05, my); ctx.stroke(); }
  else { const wide = ["happy", "love", "party", "dance"].includes(m) ? .13 : .08; ctx.beginPath(); ctx.moveTo(cx - f.w * wide, my - f.h * .02); ctx.quadraticCurveTo(cx, my + f.h * (wide > .1 ? .14 : .08), cx + f.w * wide, my - f.h * .02); ctx.stroke(); }
}
function hat(ctx, s, t, kind, b) {
  const cx = b.x + b.w / 2, top = b.y;
  if (kind === "party") { const x = cx - b.w * .18, y = top + s * .03; ctx.fillStyle = grad(ctx, y, y - s * .3, "#5b9cf6", "#9d7cf6"); ctx.beginPath(); ctx.moveTo(x - s * .11, y); ctx.lineTo(x + s * .03, y - s * .3); ctx.lineTo(x + s * .13, y + s * .01); ctx.fill(); ctx.fillStyle = "#ff6fa5"; ctx.beginPath(); ctx.arc(x + s * .03, y - s * .31, s * .035, 0, 7); ctx.fill(); }
  if (kind === "crown") { const w = s * .24, h = s * .13, x = cx - w / 2, y = top + s * .01; ctx.fillStyle = "#f5c542"; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x, y - h); ctx.lineTo(x + w * .25, y - h * .5); ctx.lineTo(x + w * .5, y - h * 1.1); ctx.lineTo(x + w * .75, y - h * .5); ctx.lineTo(x + w, y - h); ctx.lineTo(x + w, y); ctx.fill(); }
  if (kind === "beanie") { ctx.fillStyle = "#3e6be0"; ctx.beginPath(); ctx.moveTo(b.x + b.w * .12, top); ctx.quadraticCurveTo(cx, top - s * .28, b.x + b.w * .88, top); ctx.fill(); ctx.fillStyle = "#2b4fb5"; rr(ctx, b.x + b.w * .1, top - s * .02, b.w * .8, s * .07, s * .035, true); ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(cx, top - s * .15, s * .045, 0, 7); ctx.fill(); }
  if (kind === "halo") { ctx.strokeStyle = "#f5c542"; ctx.lineWidth = Math.max(1.5, s * .03); ctx.beginPath(); ctx.ellipse(cx, top - s * .1 + Math.sin(t * 2) * s * .01, b.w * .3, s * .04, 0, 0, 7); ctx.stroke(); }
  if (kind === "headphones") { ctx.strokeStyle = "#2a2d33"; ctx.lineWidth = s * .045; ctx.beginPath(); ctx.moveTo(b.x + b.w * .02, top + b.h * .35); ctx.quadraticCurveTo(cx, top - s * .24, b.x + b.w * .98, top + b.h * .35); ctx.stroke(); ctx.fillStyle = "#a6f25c"; rr(ctx, b.x - s * .05, top + b.h * .25, s * .1, s * .17, s * .04, true); rr(ctx, b.x + b.w - s * .05, top + b.h * .25, s * .1, s * .17, s * .04, true); }
}
function extras(ctx, s, t, m, b, ages, heat) {
  const glyph = { sleep: ["z", "#fff"], love: ["♥", "#ff6fa5"], dance: ["♪", "#a6f25c"], alert: ["!", "#f5c542"] }[m];
  if (glyph) for (let i = 0; i < 2; i++) { const q = (t * .6 + i * .5) % 1; ctx.globalAlpha = 1 - q; ctx.fillStyle = glyph[1]; ctx.font = `900 ${s * .15 * (.7 + q * .5)}px sans-serif`; ctx.fillText(glyph[0], b.x + b.w + s * .02 + q * s * .08, b.y + s * .02 - q * s * .25); ctx.globalAlpha = 1; }
  if (m === "party") { const cs = ["#a6f25c", "#f5c542", "#ff6fa5", "#5b9cf6"]; for (let i = 0; i < 12; i++) { const q = (t * .9 + i / 12) % 1, a = i * .63; ctx.globalAlpha = 1 - q; ctx.fillStyle = cs[i % 4]; ctx.fillRect(b.x + b.w / 2 + Math.cos(a * 3) * s * .45 * q, b.y - s * .1 + q * q * s * .5 - Math.sin(a) * s * .2, s * .035, s * .05); } ctx.globalAlpha = 1; }
  if (m === "think") {
    ctx.fillStyle = "rgba(255,255,255,.92)";
    ctx.beginPath(); ctx.arc(b.x + b.w - s * .02, b.y - s * .01, s * .018, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.arc(b.x + b.w + s * .02, b.y - s * .06, s * .026, 0, 7); ctx.fill();
    const x = b.x + b.w - s * .02, y = b.y - s * .22; rr(ctx, x, y, s * .26, s * .13, s * .065, true);
    ctx.fillStyle = "#16161a"; for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(x + s * .062 + i * s * .06, y + s * .065 - Math.max(0, Math.sin(t * 6 - i * .8)) * s * .015, s * .017, 0, 7); ctx.fill(); }
  }
  if (m === "type") {
    const L = "ASDFJKLGHQWERTYUIOPZXCVBNM", k = s * .085;
    ages.forEach((age, i) => {
      if (age >= .9) return;
      const q = age / .9, seed = (i * 97 + Math.floor((performance.now() / 1000 - age) * 10)) % 1000;
      const side = seed % 2 ? 1 : -1, spread = (seed % 100) / 100;
      const x = b.x + b.w / 2 + side * b.w * (.25 + .3 * spread) * q, y = b.y - s * .02 - q * s * .3 + q * q * s * .12;
      ctx.save(); ctx.globalAlpha = 1 - q; ctx.translate(x, y); ctx.rotate(side * q * .8);
      ctx.fillStyle = "#f4f4f6"; rr(ctx, -k / 2, -k / 2, k, k, k * .22, true);
      ctx.fillStyle = "#2a2d33"; ctx.font = `700 ${k * .5}px ui-rounded,-apple-system,sans-serif`; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(L[seed % L.length], 0, 0);
      ctx.restore();
    });
    if (heat > .15) { // a small heat bar beside Gob that fills as you type faster
      const bw = s * .022, bh = b.h * .55, x = b.x - s * .06, y = b.y + b.h * .2, k = Math.min(1, heat);
      ctx.fillStyle = "rgba(255,255,255,.12)"; rr(ctx, x, y, bw, bh, bw / 2, true);
      ctx.save(); ctx.shadowColor = "#a6f25c"; ctx.shadowBlur = s * .03 * k; ctx.fillStyle = k > .8 ? "#f5c542" : "#a6f25c"; rr(ctx, x, y + bh * (1 - k), bw, bh * k, bw / 2, true); ctx.restore();
    }
  }
}

/* ---------- one animation loop for every visible pet ---------- */
const pets = [];
let running = false;
function addPet(canvas, state) {
  const entry = { canvas, ctx: canvas.getContext("2d"), state, visible: true };
  pets.push(entry);
  new IntersectionObserver(es => es.forEach(e => entry.visible = e.isIntersecting)).observe(canvas);
  if (!running) { running = true; requestAnimationFrame(frame); }
  return entry;
}
const mouse = { x: innerWidth / 2, y: innerHeight / 2 };
addEventListener("pointermove", e => { mouse.x = e.clientX; mouse.y = e.clientY; }, { passive: true });
function frame(now) {
  const t = reduce || STATIC ? 1.2 : now / 1000;
  for (const p of pets) {
    if (!p.visible) continue;
    const r = p.canvas.getBoundingClientRect();
    if (!p.state.fixedLook) {
      p.state.look = Math.max(-1, Math.min(1, (mouse.x - (r.left + r.width / 2)) / 350));
      p.state.lookY = Math.max(-1, Math.min(1, (mouse.y - (r.top + r.height / 2)) / 350));
    }
    if (p.state.until && now > p.state.until) { p.state.mood = p.state.rest || "idle"; p.state.until = 0; }
    drawPet(p.ctx, p.canvas.width, t, p.state);
  }
  requestAnimationFrame(frame);
}
const react = (p, mood, ms) => { p.state.mood = mood; p.state.until = performance.now() + ms; };

// Type anywhere on the page (outside a text field) and every pet on screen types along.
addEventListener("keydown", e => {
  if (e.repeat || e.metaKey || e.ctrlKey) return;
  keyTimes.push(performance.now()); while (keyTimes.length > 30) keyTimes.shift();
  for (const p of pets) if (p.visible && (!p.state.until || p.state.mood === "type")) react(p, "type", 800);
});

// Any <canvas data-gob='{"char":"candy","hue":.55}'> becomes a pet.
document.querySelectorAll("canvas[data-gob]").forEach(c => addPet(c, Object.assign({ hue: .3, mood: "idle", rest: "idle" }, JSON.parse(c.dataset.gob || "{}"))));

window.Gob = { addPet, react, keyTimes, SPECIES, rarity, hsl, reduce, STATIC, drawPet };
})();
