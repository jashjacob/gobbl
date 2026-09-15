// Shared page behaviour: analytics events, nav, reveals, the boot loader,
// and lazy loading of the interactive demos (js/demos.js).
(() => {
const root = document.documentElement;
const STATIC = root.classList.contains("static");
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];

// Conversion events for GA: which call to action people use.
const track = (name, params) => { try { window.gtag && gtag("event", name, params || {}); } catch (_) {} };
window.track = track;
document.addEventListener("click", e => {
  const a = e.target.closest("a"); if (!a) return;
  const where = a.closest("nav") ? "nav" : a.closest(".hero") ? "hero" : a.closest(".final") ? "final" : "page";
  if (a.href.includes("github.com/xeveio/gobbl")) track("github_click", { placement: where });
  else if (a.getAttribute("href") === "/download") track("download_click", { placement: where });
});

// Nav shrinks on scroll; a thin progress bar tracks the page.
const progress = $("#progress"), nav = $("#nav");
const onScroll = () => {
  const max = root.scrollHeight - innerHeight;
  if (progress) progress.style.transform = `scaleX(${max > 0 ? scrollY / max : 0})`;
  if (nav) nav.classList.toggle("small", scrollY > 40);
};
addEventListener("scroll", onScroll, { passive: true }); onScroll();
// Close the mobile menu after picking a link.
$$(".menu a").forEach(a => a.addEventListener("click", () => a.closest("details").open = false));

// Reveals: content is only hidden once this script runs (see the .js class).
if (STATIC || reduce) $$(".reveal").forEach(el => el.classList.add("in"));
else {
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: .12 });
  $$(".reveal").forEach(el => io.observe(el));
}

if (!reduce && !STATIC && matchMedia("(pointer: fine)").matches) {
  $$(".magnetic").forEach(b => {
    b.addEventListener("pointermove", e => { const r = b.getBoundingClientRect(); b.style.transform = `translate(${(e.clientX - r.left - r.width / 2) * .09}px,${(e.clientY - r.top - r.height / 2) * .14}px)`; });
    b.addEventListener("pointerleave", () => b.style.transform = "");
  });
  $$(".card").forEach(c => {
    c.addEventListener("pointermove", e => { const r = c.getBoundingClientRect(), x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height; c.style.transform = `perspective(900px) rotateX(${(.5 - y) * 5}deg) rotateY(${(x - .5) * 5}deg)`; c.style.setProperty("--mx", x * 100 + "%"); c.style.setProperty("--my", y * 100 + "%"); });
    c.addEventListener("pointerleave", () => c.style.transform = "");
  });
}

// Count-up stats.
const counter = new IntersectionObserver(es => es.forEach(e => {
  if (!e.isIntersecting) return; counter.unobserve(e.target);
  const el = e.target, to = +el.dataset.count, pre = el.dataset.prefix || "", suf = el.dataset.suffix || "", dec = +(el.dataset.dec || 0);
  if (STATIC || reduce || to === 0) { el.textContent = pre + to.toFixed(dec) + suf; return; }
  const t0 = performance.now(); (function tick(n) { const k = Math.min(1, (n - t0) / 1200), v = to * (1 - Math.pow(1 - k, 3)); el.textContent = pre + v.toFixed(dec) + suf; if (k < 1) requestAnimationFrame(tick); })(t0);
}), { threshold: .6 });
$$("[data-count]").forEach(el => counter.observe(el));

// Marquees loop seamlessly with a second copy of their items.
$$(".marquee .track").forEach(t => { t.insertAdjacentHTML("beforeend", t.innerHTML.replace(/<span/g, '<span aria-hidden="true"')); });

// Feature nav: highlight the section in view and keep its chip visible.
const fnav = $(".fnav");
if (fnav) {
  const links = $$("a", fnav), map = new Map(links.map(a => [a.getAttribute("href").slice(1), a]));
  const spy = new IntersectionObserver(es => es.forEach(e => {
    if (!e.isIntersecting) return;
    links.forEach(a => a.classList.remove("on"));
    const a = map.get(e.target.id); if (!a) return;
    a.classList.add("on");
    const bar = a.parentElement; bar.scrollTo({ left: a.offsetLeft - bar.clientWidth / 2 + a.offsetWidth / 2, behavior: reduce ? "auto" : "smooth" });
  }), { rootMargin: "-45% 0px -50% 0px" });
  map.forEach((a, id) => { const s = document.getElementById(id); if (s) spy.observe(s); });
}

// Boot loader (home, first visit per tab): the computer's CRT line sweeps,
// it says "Hi!", then the page fades in. Click or any key skips it.
const boot = $("#boot");
if (boot && root.classList.contains("boot")) {
  try { sessionStorage.setItem("gobBoot", "1"); } catch (_) {}
  const done = () => { boot.classList.add("out"); setTimeout(() => { root.classList.remove("boot"); boot.remove(); }, 450); };
  boot.addEventListener("click", done); addEventListener("keydown", done, { once: true });
  const c = $("canvas", boot);
  if (window.Gob && c) {
    const pet = Gob.addPet(c, { hue: .3, char: "retro", mood: "idle", scan: 0, text: "", fixedLook: true });
    const t0 = performance.now();
    (function step(n) {
      const k = (n - t0) / 700;
      if (k < 1) { pet.state.scan = k; requestAnimationFrame(step); return; }
      pet.state.scan = null; pet.state.text = "Hi!";
      setTimeout(() => { pet.state.text = null; Gob.react(pet, "happy", 2000); }, 650);
      setTimeout(done, 1150);
    })(t0);
  } else setTimeout(done, 300);
} else if (boot) boot.remove();

// Demos load when the first one is about to scroll into view.
const demos = $$("[data-demo]");
if (demos.length) {
  let loaded = false;
  const load = () => { if (loaded) return; loaded = true; const s = document.createElement("script"); s.src = "/js/demos.js"; s.defer = true; document.body.appendChild(s); };
  if (STATIC) load();
  else {
    const lazy = new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) { lazy.disconnect(); load(); } }, { rootMargin: "800px 0px" });
    demos.forEach(d => lazy.observe(d));
  }
}

// Download prompt: pay what you want, or download free. Skipped once someone has paid
// (/thanks sets the flag) and for modified clicks. Its choices are buttons, not links, so
// the head's "download_clicked" handler counts each download intent once.
const paid = () => { try { return localStorage.getItem("gobbl_paid") === "1"; } catch (_) { return false; } };
let dlg;
const payPrompt = () => {
  if (!dlg) {
    const css = document.createElement("style");
    css.textContent = `dialog.pay{width:min(440px,calc(100% - 32px));padding:32px 28px 24px;border-radius:24px;background:var(--surface,#131418);color:var(--text,#f2f3f5);border:1px solid var(--line2,rgba(255,255,255,.15));box-shadow:0 40px 80px -30px #000;text-align:center}
dialog.pay::backdrop{background:rgba(0,0,0,.6);backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px)}
dialog.pay[open]{animation:payIn .3s var(--spring,ease)}
@keyframes payIn{from{opacity:0;transform:scale(.94)}}
@media (prefers-reduced-motion:reduce){dialog.pay[open]{animation:none}}
dialog.pay h2{font-size:28px;letter-spacing:-.02em;margin:0 0 10px}
dialog.pay p{color:var(--muted,#a3a9b1);font-size:16px;margin:0 0 22px;text-wrap:pretty}
dialog.pay .cta{justify-content:center}
dialog.pay .fine{font-size:13px;color:var(--faint,#858b94);margin:16px 0 0}
dialog.pay .x{position:absolute;top:12px;right:12px;width:34px;height:34px;border-radius:50%;font-size:22px;line-height:1;color:var(--muted,#a3a9b1)}
dialog.pay .x:hover{background:rgba(255,255,255,.08);color:var(--text,#f2f3f5)}`;
    document.head.appendChild(css);
    dlg = document.createElement("dialog");
    dlg.className = "pay";
    dlg.setAttribute("aria-labelledby", "pay-h");
    dlg.innerHTML = `<h2 id="pay-h">Gobbl is free.</h2>
<p>If it earns a spot in your notch, you can pay what you want. We suggest $20, one time. It unlocks nothing: it keeps Gobbl free and open source.</p>
<div class="cta"><button type="button" class="btn primary" data-choice="pay" autofocus>Pay what you want</button><button type="button" class="btn ghost" data-choice="free">Download free</button></div>
<p class="fine">Paying opens checkout in a new tab. Your download starts either way.</p>
<button type="button" class="x" aria-label="Close">&times;</button>`;
    document.body.appendChild(dlg);
    dlg.addEventListener("click", e => {
      if (e.target === dlg || e.target.closest(".x")) { dlg.close(); return; }
      const b = e.target.closest("[data-choice]"); if (!b) return;
      const choice = b.dataset.choice;
      track("download_choice", { choice });
      try { window.posthog && posthog.capture("download_choice", { choice }); } catch (_) {}
      if (choice === "pay") window.open("/support", "_blank", "noopener");
      dlg.close();
      location.href = "/download";
    });
  }
  dlg.showModal();
};
document.addEventListener("click", e => {
  const a = e.target.closest('a[href="/download"]');
  if (!a || paid() || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return;
  if (typeof HTMLDialogElement !== "function") return;
  e.preventDefault();
  payPrompt();
});
})();
