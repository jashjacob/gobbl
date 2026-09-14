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
})();
