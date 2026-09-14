// Generates the static Gobbl site into site/. Run: node build.mjs
import { writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";
import { pages, ORIGIN } from "./pages.mjs";

const SITE = new URL("../../site", import.meta.url).pathname.replace(/\/$/, "");
const TODAY = "2026-09-14";

const ICONS = {
  tray: '<path d="M4 13l2.5-7h11L20 13v5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M4 13h4.5l1.5 2.5h4l1.5-2.5H20"/>',
  wand: '<path d="M4.5 19.5l10-10"/><path d="M13 8l3 3"/><path d="M18 3.5v3M16.5 5h3"/><path d="M19.5 11.5v2M18.5 12.5h2"/><path d="M9.5 3.5v2M8.5 4.5h2"/>',
  clipboard: '<rect x="5.5" y="4.5" width="13" height="16" rx="2"/><path d="M9 3h6v3H9z"/><path d="M9 11h6M9 15h4"/>',
  music: '<path d="M9 17.5V6l10-2v11.5"/><circle cx="7" cy="17.5" r="2"/><circle cx="17" cy="15.5" r="2"/>',
  speaker: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18 6.5a7.5 7.5 0 0 1 0 11"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2.5 12h2M19.5 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4"/>',
  moon: '<path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  timer: '<circle cx="12" cy="13.5" r="7"/><path d="M12 13.5V10M10 3h4M18 7l1.5-1.5"/>',
  bolt: '<path d="M13 3L5 13.5h6L10 21l8-10.5h-6z"/>',
  terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M7.5 10l2.5 2-2.5 2M12.5 15h4"/>',
  film: '<rect x="3.5" y="5" width="17" height="14" rx="2"/><path d="M7.5 5v14M16.5 5v14M3.5 9.5h4M3.5 14.5h4M16.5 9.5h4M16.5 14.5h4"/>',
  basket: '<path d="M3.5 10h17l-1.6 8.3a2 2 0 0 1-2 1.7H7.1a2 2 0 0 1-2-1.7z"/><path d="M8 10l3-5.5M16 10l-3-5.5M9.5 13.5v3M14.5 13.5v3"/>',
  monitor: '<rect x="3" y="4" width="18" height="12.5" rx="2"/><path d="M9 20.5h6M12 16.5v4"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5M12 14.5v2"/>',
  keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6.5 10h1M10.5 10h1M14.5 10h1M8 14h8"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
  github: '<path d="M9 19.5c-4 1.2-4-2-5.5-2.5M15 21.5v-3.2a2.8 2.8 0 0 0-.8-2.2c2.6-.3 5.3-1.3 5.3-5.8a4.5 4.5 0 0 0-1.2-3.1 4.2 4.2 0 0 0-.1-3.1s-1-.3-3.2 1.2a11 11 0 0 0-6 0C6.8 3.8 5.8 4.1 5.8 4.1a4.2 4.2 0 0 0-.1 3.1 4.5 4.5 0 0 0-1.2 3.1c0 4.5 2.7 5.5 5.3 5.8a2.8 2.8 0 0 0-.8 2.2v3.2"/>',
  box: '<path d="M3.5 7.5L12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5L12 11.5l8.5-4M12 11.5v9M7.8 5.5l8.4 4"/>',
  download: '<path d="M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>',
  drop: '<path d="M12 3.5s6 6.3 6 10.5a6 6 0 0 1-12 0c0-4.2 6-10.5 6-10.5z"/>',
  scan: '<path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16M9 9h6M12 9v6"/>',
  trend: '<path d="M3.5 17l5.5-5.5 4 4 7.5-7.5M15 8h5.5v5.5"/>',
  chat: '<path d="M4 5.5h16v10H9.5L5 19.5v-4H4z"/><path d="M8 9.5h8M8 12.5h5"/>',
  brain: '<path d="M9 4.5a3 3 0 0 0-3 3 3 3 0 0 0-2 5.2A3 3 0 0 0 7 17.5a2.5 2.5 0 0 0 5 .5V6a2 2 0 0 0-3-1.5z"/><path d="M15 4.5a3 3 0 0 1 3 3 3 3 0 0 1 2 5.2 3 3 0 0 1-3 4.8 2.5 2.5 0 0 1-5 .5"/>',
  plug: '<path d="M9 3v5M15 3v5M6.5 8h11v3a5.5 5.5 0 0 1-11 0z"/><path d="M12 16.5V21"/>',
  shield: '<path d="M12 3l7.5 3v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6z"/><path d="M9 12l2 2 4-4"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  users: '<circle cx="9" cy="8.5" r="3.5"/><path d="M3 20a6 6 0 0 1 12 0"/><path d="M15.5 5.2a3.5 3.5 0 0 1 0 6.6M17.5 14.2A6 6 0 0 1 21 20"/>',
  bell: '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 1.5h-15z"/><path d="M10 20.5h4"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M4 4l16 16"/><path d="M9.5 6A9.6 9.6 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-3 3.6M6.3 7.8A16 16 0 0 0 2.5 12S6 18.5 12 18.5a9 9 0 0 0 4-1"/>',
  pause: '<rect x="6.5" y="5" width="3.5" height="14" rx="1"/><rect x="14" y="5" width="3.5" height="14" rx="1"/>',
  trash: '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  list: '<path d="M9 6.5h11M9 12h11M9 17.5h11"/><circle cx="4.8" cy="6.5" r="1"/><circle cx="4.8" cy="12" r="1"/><circle cx="4.8" cy="17.5" r="1"/>',
  code: '<path d="M8.5 7L3.5 12l5 5M15.5 7l5 5-5 5M13.5 4.5l-3 15"/>',
  wave: '<path d="M3 12h2M7 8v8M11 5v14M15 9v6M19 7v10M21 12h0"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5z"/>',
  layers: '<path d="M12 3.5l8.5 4.5-8.5 4.5L3.5 8z"/><path d="M3.5 12.5L12 17l8.5-4.5M3.5 16.5L12 21l8.5-4.5"/>',
  hat: '<path d="M4 17.5h16"/><path d="M6.5 17.5l2-9.5a3.5 3.5 0 0 1 7 0l2 9.5"/><path d="M8 13h8"/>',
  cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx="1"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/>',
  user: '<circle cx="12" cy="8.5" r="4"/><path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"/>',
  log: '<rect x="5" y="3.5" width="14" height="17" rx="2"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>',
  heart: '<path d="M12 19.5s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7a4.3 4.3 0 0 1 7.5 2.5c0 5.6-7.5 10-7.5 10z"/>'
};
const sprite = `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>${Object.entries(ICONS).map(([k, v]) => `<symbol id="i-${k}" viewBox="0 0 24 24">${v}</symbol>`).join("")}</defs></svg>`;

const NAV = [["/features", "Features"], ["/dictation", "Dictation"], ["/memory", "Memory"], ["/compare/", "Compare"], ["/faq", "FAQ"]];
const ic = n => `<svg class="i" aria-hidden="true"><use href="#i-${n}"/></svg>`;

function nav(p) {
  const links = NAV.map(([h, l]) => `<a href="${h}"${p.url === h ? ' aria-current="page"' : ""}>${l}</a>`).join("");
  return `<header class="top" id="nav">
  <a class="brand" href="/" aria-label="Gobbl home"><img src="${p.icon}" alt="" width="26" height="26">Gobbl</a>
  <nav class="links" aria-label="Main">${links}</nav>
  <a class="btn primary small magnetic" href="https://github.com/xeveio/gobbl">${ic("github")}<span class="gh">Star on GitHub</span></a>
  <details class="menu"><summary aria-label="Menu">${ic("menu")}</summary><nav class="sheet" aria-label="Mobile">${links}<a href="/privacy">Privacy</a><a href="https://github.com/xeveio/gobbl">GitHub</a></nav></details>
</header>`;
}

function footer() {
  const col = (h, items) => `<div><p class="fh">${h}</p>${items.map(([u, l]) => `<a href="${u}">${l}</a>`).join("")}</div>`;
  return `<footer class="site"><div class="wrap">
  <div class="fgrid">
    <div class="fabout"><a class="brand" href="/"><img src="/img/icon.png" alt="" width="26" height="26" loading="lazy">Gobbl</a><p>A free, open-source notch app for Mac with a pet that lives in the notch. Shelf, clipboard, music, dictation, AI writing and memory. Made by <a href="https://xeve.io">Xeve</a>.</p></div>
    ${col("Product", [["/features", "All features"], ["/dictation", "Offline dictation"], ["/memory", "Screen memory"], ["/privacy", "Privacy"], ["/faq", "FAQ"], ["/download", "Download"]])}
    ${col("Compare", [["/compare/wispr-flow", "Gobbl vs Wispr Flow"], ["/compare/droppy", "Gobbl vs Droppy"], ["/compare/notchnook", "Gobbl vs NotchNook"], ["/compare/goldfish", "Gobbl vs Goldfish"], ["/compare/", "All comparisons"]])}
    ${col("Open source", [["https://github.com/xeveio/gobbl", "GitHub"], ["https://github.com/xeveio/gobbl/releases", "Releases"], ["https://github.com/xeveio/gobbl/blob/main/LICENSE", "MIT License"], ["https://github.com/xeveio/gobbl/issues", "Report an issue"], ["https://xeve.io", "Xeve"]])}
  </div>
  <div class="fine2"><span>&copy; 2026 Xeve. Gobbl is free software under the MIT License.</span><span>macOS 14 or later. Not affiliated with Apple.</span></div>
</div></footer>`;
}

function crumbs(p) {
  if (!p.crumbs) return "";
  const all = [["/", "Home"], ...p.crumbs];
  return `<nav class="crumbs" aria-label="Breadcrumb"><ol>${all.map(([u, l], i) => i === all.length - 1 ? `<li aria-current="page">${l}</li>` : `<li><a href="${u}">${l}</a></li>`).join("")}</ol></nav>`;
}
function breadcrumbLD(p) {
  const all = [["/", "Home"], ...p.crumbs];
  return { "@context": "https://schema.org", "@type": "BreadcrumbList", itemListElement: all.map(([u, l], i) => ({ "@type": "ListItem", position: i + 1, name: l, item: ORIGIN + u })) };
}

const esc = s => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

function render(p) {
  const canonical = ORIGIN + p.url;
  const ld = [...(p.ld || [])];
  if (p.crumbs) ld.push(breadcrumbLD(p));
  const boot = p.boot ? "try{if(!c.contains('static')&&!matchMedia('(prefers-reduced-motion: reduce)').matches&&!sessionStorage.getItem('gobBoot'))c.add('boot')}catch(e){}" : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(p.title)}</title>
<meta name="description" content="${esc(p.desc)}">
<link rel="canonical" href="${canonical}">
<meta name="robots" content="${p.noindex ? "noindex" : "index, follow, max-image-preview:large"}">
<link rel="icon" href="${p.icon}">
<link rel="apple-touch-icon" href="${p.icon}">
<meta name="theme-color" content="#08080a">
<meta name="color-scheme" content="dark">
<meta property="og:type" content="${p.ogType || "website"}">
<meta property="og:site_name" content="Gobbl">
<meta property="og:title" content="${esc(p.ogTitle || p.title)}">
<meta property="og:description" content="${esc(p.desc)}">
<meta property="og:url" content="${canonical}">
<meta property="og:image" content="${ORIGIN}/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Gob, a small retro computer with a smiling face, peeking out of a MacBook notch next to the words: Your notch has a pet.">
<meta property="og:locale" content="en_US">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(p.ogTitle || p.title)}">
<meta name="twitter:description" content="${esc(p.desc)}">
<meta name="twitter:image" content="${ORIGIN}/og.png">
<meta name="twitter:image:alt" content="Gob, the Gobbl pet, in a MacBook notch.">
<link rel="preconnect" href="https://www.googletagmanager.com">
<link rel="preload" href="/js/gob.js" as="script">
<!-- Google Analytics (Xeve property, shared with xeve.io). The website only: the Gobbl app has no analytics. -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-21SSB74NQD"></script>
<script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}gtag('js',new Date());gtag('config','G-21SSB74NQD');
(function(){var c=document.documentElement.classList;c.add('js');if(/[?&]static\\b/.test(location.search))c.add('static');${boot}})();</script>
${ld.map(o => `<script type="application/ld+json">\n${JSON.stringify(o)}\n</script>`).join("\n")}
<style>
${CSS}${p.css || ""}
</style>
</head>
<body class="${p.bodyClass || ""}">
${sprite}
<a class="skip" href="#main">Skip to content</a>
<div id="progress" aria-hidden="true"></div>
${p.boot ? `<div id="boot" aria-hidden="true"><canvas width="320" height="320"></canvas><span>gobbl</span></div>` : ""}
${nav(p)}
<main id="main">
${p.crumbs ? `<div class="wrap crumbs-wrap">${crumbs(p)}</div>` : ""}
${p.body}
</main>
${footer()}
<script src="/js/gob.js" defer></script>
<script src="/js/site.js" defer></script>
</body>
</html>
`;
}

const CSS = `:root{--bg:#08080a;--bg2:#0d0e11;--surface:#131418;--raised:#1a1c21;--line:rgba(255,255,255,.08);--line2:rgba(255,255,255,.15);--text:#f2f3f5;--soft:#cfd3d9;--muted:#a3a9b1;--faint:#858b94;--lime:#a6f25c;--lime2:#6fd39b;--pink:#ff6fa5;--gold:#f5c542;--blue:#5b9cf6;--red:#ef6b63;--ease:cubic-bezier(.2,.8,.2,1);--spring:cubic-bezier(.3,1.5,.5,1)}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:130px;background:var(--bg)}
body{margin:0;background:var(--bg);color:var(--text);font:17px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Inter,system-ui,sans-serif;-webkit-font-smoothing:antialiased;overflow-x:clip}
a{color:inherit;text-decoration:none}
button{font:inherit;color:inherit;border:0;background:none;cursor:pointer}
img,canvas,svg{max-width:100%}
:focus-visible{outline:2px solid var(--lime);outline-offset:3px;border-radius:8px}
::selection{background:var(--lime);color:#000}
.wrap{max-width:1160px;margin:0 auto;padding:0 24px}
.skip{position:absolute;left:12px;top:-80px;z-index:200;background:var(--lime);color:#000;padding:10px 14px;border-radius:10px;font-weight:700}.skip:focus{top:12px}
#progress{position:fixed;top:0;left:0;height:2px;width:100%;transform-origin:0 50%;transform:scaleX(0);background:var(--lime);opacity:.7;z-index:60}
.i{width:1.1em;height:1.1em;flex:none;fill:none;stroke:currentColor;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round;vertical-align:-.18em}
.link{color:var(--lime);text-decoration:underline;text-underline-offset:3px;text-decoration-thickness:1px}
.link:hover{text-decoration-thickness:2px}

/* top nav */
.top{position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:50;display:flex;align-items:center;gap:22px;padding:7px 7px 7px 16px;border-radius:999px;background:rgba(18,19,23,.62);backdrop-filter:blur(18px) saturate(1.4);-webkit-backdrop-filter:blur(18px) saturate(1.4);border:1px solid var(--line);transition:background .3s;width:max-content;max-width:calc(100% - 24px)}
.top.small{background:rgba(18,19,23,.88)}
.brand{display:flex;gap:9px;align-items:center;font-weight:800;letter-spacing:.01em}
.brand img{width:26px;height:26px}
.links{display:flex;gap:18px;font-size:14px;color:var(--muted)}
.links a{padding:4px 2px}.links a:hover,.links a[aria-current]{color:var(--text)}
.menu{display:none;position:relative}
.menu summary{list-style:none;width:38px;height:38px;display:grid;place-items:center;border-radius:50%;background:rgba(255,255,255,.07);cursor:pointer}
.menu summary::-webkit-details-marker{display:none}
.menu .sheet{position:absolute;right:0;top:48px;min-width:230px;display:grid;padding:8px;border-radius:18px;background:#15161a;border:1px solid var(--line2);box-shadow:0 30px 60px -20px #000}
.sheet a{padding:11px 12px;border-radius:10px;color:var(--soft)}.sheet a:hover,.sheet a[aria-current]{background:rgba(255,255,255,.06);color:var(--text)}
.btn{display:inline-flex;align-items:center;gap:9px;padding:13px 22px;border-radius:999px;font-weight:700;font-size:15.5px;transition:transform .25s var(--spring),box-shadow .3s,background .2s;white-space:nowrap}
.btn.small{padding:8px 14px;font-size:13.5px}
.btn.primary{background:var(--lime);color:#07120a;box-shadow:0 8px 24px -12px rgba(166,242,92,.45)}
.btn.primary:hover{box-shadow:0 0 0 4px rgba(166,242,92,.14),0 10px 30px -12px rgba(166,242,92,.55)}
.btn.ghost{background:rgba(255,255,255,.06);border:1px solid var(--line2)}
.btn.ghost:hover{background:rgba(255,255,255,.1)}
.btn small{opacity:.7;font-weight:600}
.cta{display:flex;gap:12px;flex-wrap:wrap}
.badge{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:700;padding:3px 10px;border-radius:999px;background:rgba(245,197,66,.1);color:var(--gold);border:1px solid rgba(245,197,66,.3);letter-spacing:.02em;vertical-align:middle;white-space:nowrap}
.badge.lime{background:rgba(166,242,92,.08);color:var(--lime);border-color:rgba(166,242,92,.25)}

/* boot loader */
#boot{display:none}
.boot #boot{display:grid;place-content:center;justify-items:center;gap:6px;position:fixed;inset:0;z-index:100;background:var(--bg);animation:bootSafety .4s 3.4s forwards;cursor:pointer}
#boot canvas{width:160px;height:160px}
#boot span{font:600 13px ui-monospace,Menlo,monospace;letter-spacing:.3em;color:var(--faint);text-transform:uppercase}
#boot.out{opacity:0;transition:opacity .45s}
@keyframes bootSafety{to{opacity:0;visibility:hidden}}

/* sections */
section{position:relative;padding:130px 0}
.kicker{display:flex;gap:10px;align-items:center;font-size:12.5px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--lime);margin-bottom:14px}
h1,h2,h3{text-wrap:balance}
h2{font-size:clamp(32px,4.4vw,54px);letter-spacing:-.03em;line-height:1.05;margin:0 0 18px;font-weight:780}
.sub{color:var(--muted);font-size:clamp(17px,1.6vw,19px);max-width:640px;margin:0 0 52px;text-wrap:pretty}
.center{text-align:center}.center .sub{margin-left:auto;margin-right:auto}.center .kicker{justify-content:center}
.more{display:inline-flex;gap:8px;align-items:center;margin-top:28px;font-weight:650;color:var(--lime)}
.more .i{transition:transform .25s var(--ease)}.more:hover .i{transform:translateX(4px)}
.js .reveal{opacity:0;transform:translateY(34px);transition:opacity .9s var(--ease),transform .9s var(--ease);transition-delay:calc(var(--i,0)*80ms)}
.js .reveal.in{opacity:1;transform:none}
/* If site.js never runs, reveal everything after a moment. */
.js .reveal{animation:safety 0s 3s forwards}.js .reveal.in{animation:none}
@keyframes safety{to{opacity:1;transform:none}}

/* page hero (subpages) */
.crumbs-wrap{padding-top:108px}
.crumbs ol{display:flex;flex-wrap:wrap;gap:6px;list-style:none;margin:0;padding:0;font-size:13.5px;color:var(--faint)}
.crumbs li+li::before{content:"/";margin-right:6px;color:#4d5259}
.crumbs a:hover{color:var(--text)}
.phero{padding:34px 0 30px}
.phero .grid{display:grid;grid-template-columns:minmax(0,1fr) 260px;gap:40px;align-items:center}
.phero h1{font-size:clamp(38px,5.6vw,66px);line-height:1.02;letter-spacing:-.04em;margin:0 0 18px;font-weight:820}
.phero .lede{font-size:clamp(17px,1.8vw,20px);color:var(--muted);max-width:680px;margin:0 0 28px;text-wrap:pretty}
.phero canvas{width:100%;aspect-ratio:1;height:auto}
.phero .pet{position:relative;border-radius:28px;background:radial-gradient(circle at 50% 45%,rgba(166,242,92,.16),transparent 62%),var(--surface);border:1px solid var(--line);padding:18px}
.meta-row{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:14px;color:var(--faint);margin-top:18px}
.meta-row span{display:inline-flex;gap:6px;align-items:center}.meta-row .i{color:var(--lime)}

/* prose + layout for subpages */
.page{display:grid;grid-template-columns:minmax(0,1fr) 280px;gap:64px;align-items:start;padding-bottom:40px}
.prose{max-width:760px}
.prose section{padding:0}
@media (max-width:900px){.aside .toc{display:none}}
.prose h2{font-size:clamp(27px,3.2vw,38px);margin:72px 0 16px}
.prose h2:first-child{margin-top:20px}
.prose h3{font-size:20px;letter-spacing:-.01em;margin:34px 0 8px}
.prose p,.prose li{color:var(--soft);text-wrap:pretty}
.prose a:not(.btn){color:var(--lime);text-decoration:underline;text-underline-offset:3px;text-decoration-thickness:1px}
.prose ul,.prose ol{padding-left:1.3em}.prose li{margin:7px 0}
.prose li::marker{color:var(--faint)}
.prose strong{color:var(--text)}
.prose code,.kbd{font:14px ui-monospace,SFMono-Regular,Menlo,monospace;background:rgba(255,255,255,.07);border:1px solid var(--line);padding:1px 6px;border-radius:6px;color:var(--text)}
.tldr{background:var(--surface);border:1px solid var(--line);border-left:3px solid var(--lime);border-radius:14px;padding:18px 22px;margin:8px 0 10px}
.tldr p{margin:0}.tldr p+p{margin-top:8px}
.aside{position:sticky;top:96px;display:grid;gap:14px}
.aside .box{background:var(--surface);border:1px solid var(--line);border-radius:20px;padding:20px}
.aside .toc a{display:block;padding:5px 0;color:var(--muted);font-size:14.5px}.aside .toc a:hover{color:var(--text)}
.aside canvas{width:120px;height:120px;display:block;margin:0 auto 6px}
.aside .box p{margin:0 0 14px;color:var(--muted);font-size:14.5px;text-align:center}
.aside .btn{width:100%;justify-content:center}
.fh{font-size:12.5px;letter-spacing:.12em;text-transform:uppercase;color:var(--faint);margin:0 0 10px;font-weight:700}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:22px 0}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:22px 0}
.tile2{background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:20px}
.tile2 h3{margin:0 0 6px;font-size:17px;display:flex;gap:9px;align-items:center}.tile2 h3 .i{color:var(--lime)}
.tile2 p{margin:0;font-size:15px;color:var(--muted)}
.steps3{counter-reset:s;display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:22px 0;padding:0;list-style:none}
.steps3 li{counter-increment:s;background:var(--surface);border:1px solid var(--line);border-radius:18px;padding:20px;margin:0;color:var(--muted);font-size:15px}
.steps3 li::before{content:counter(s,decimal-leading-zero);display:block;font:600 13px ui-monospace,Menlo,monospace;color:var(--lime);margin-bottom:8px}
.steps3 b{display:block;color:var(--text);font-size:17px;margin-bottom:4px}
.data{width:100%;border-collapse:collapse;font-size:15px;margin:18px 0}
.data th,.data td{text-align:left;padding:11px 12px;border-bottom:1px solid var(--line);vertical-align:top}
.data th{color:var(--faint);font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
.data td:first-child{color:var(--text);font-weight:600}
.data td{color:var(--soft)}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}

/* cards */
.bento{display:grid;grid-template-columns:repeat(6,1fr);gap:14px}
.card{position:relative;grid-column:span 2;border-radius:20px;padding:26px;background:linear-gradient(180deg,var(--raised),var(--surface));border:1px solid var(--line);overflow:hidden;transition:transform .35s var(--ease),border-color .3s}
.card:hover{border-color:var(--line2)}
.card.wide{grid-column:span 3}
.card .ico{width:40px;height:40px;border-radius:11px;display:grid;place-items:center;margin-bottom:16px;background:rgba(166,242,92,.1);border:1px solid rgba(166,242,92,.18);color:var(--lime)}
.card .ico .i{width:22px;height:22px}
.card h3{margin:0 0 6px;font-size:18px;letter-spacing:-.01em}
.card p{margin:0;color:var(--muted);font-size:15px}
.card a.link{font-size:14.5px;display:inline-block;margin-top:10px}
.card::before{content:"";position:absolute;inset:0;background:radial-gradient(400px circle at var(--mx,50%) var(--my,50%),rgba(255,255,255,.05),transparent 40%);opacity:0;transition:opacity .3s;pointer-events:none}
.card:hover::before{opacity:1}

/* comparison table */
.tbl{overflow-x:auto;border:1px solid var(--line);border-radius:20px;background:var(--surface);-webkit-overflow-scrolling:touch}
table.cmp{border-collapse:separate;border-spacing:0;width:100%;min-width:var(--minw,1060px);font-size:14px}
.cmp caption{text-align:left;padding:16px 16px 4px;color:var(--muted);font-size:13.5px}
.cmp th,.cmp td{padding:13px 14px;text-align:left;vertical-align:top;border-bottom:1px solid var(--line)}
.cmp tr:last-child>*{border-bottom:0}
.cmp thead th{font-size:13.5px;color:var(--soft);font-weight:750;background:var(--raised);white-space:nowrap}
.cmp thead th small{display:block;font-weight:600;color:var(--faint);font-size:11.5px;letter-spacing:.04em;text-transform:uppercase}
.cmp tbody th{position:sticky;left:0;background:var(--surface);font-weight:650;color:var(--text);min-width:140px;z-index:1;box-shadow:1px 0 0 var(--line)}
.cmp thead th:first-child{position:sticky;left:0;z-index:2}
.cmp .us{background:rgba(166,242,92,.045)}.cmp thead .us{color:var(--lime);background:#1b2117}
.v{display:flex;gap:8px;align-items:flex-start;line-height:1.4;color:var(--soft)}
.v::before{content:"";flex:none;width:8px;height:8px;border-radius:50%;margin-top:6px;background:var(--faint)}
.v.y::before{background:var(--lime)}.v.p::before{background:var(--gold)}.v.n::before{background:var(--red)}.v.u::before{background:transparent;border:1.5px solid var(--faint)}
.legend{display:flex;gap:8px 20px;flex-wrap:wrap;font-size:13.5px;color:var(--muted);margin-top:14px}
.legend .v{color:var(--muted)}
.note{font-size:14px;color:var(--faint);margin-top:14px;max-width:820px}
.note a{color:var(--muted);text-decoration:underline;text-underline-offset:3px}

/* faq */
.faq details{border-bottom:1px solid var(--line);padding:18px 0}
.faq summary{cursor:pointer;font-weight:620;font-size:18px;list-style:none;display:flex;justify-content:space-between;gap:20px}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"+";color:var(--faint);font-size:22px;line-height:1;transition:transform .3s}
.faq details[open] summary::after{transform:rotate(45deg)}
.faq details p{color:var(--muted);margin:12px 0 0;max-width:760px}
.faq details a{color:var(--lime);text-decoration:underline;text-underline-offset:3px}
.faq h3{font-size:inherit;margin:0;font-weight:inherit}

/* final + footer */
.final{text-align:center;overflow:hidden}
.final canvas{width:170px;height:170px;margin-bottom:8px}
.final .cta{justify-content:center}
footer.site{border-top:1px solid var(--line);padding:56px 0 44px;margin-top:30px;background:var(--bg2)}
.fgrid{display:grid;grid-template-columns:1.5fr repeat(3,1fr);gap:32px}
.fgrid a{display:block;color:var(--muted);padding:4px 0;font-size:14.5px}.fgrid a:hover{color:var(--text)}
.fabout .brand{display:flex;padding:0;color:var(--text);margin-bottom:12px}
.fabout p{color:var(--faint);font-size:14.5px;margin:0;max-width:340px}.fabout p a{display:inline;color:var(--muted);text-decoration:underline;text-underline-offset:3px}
.fine2{margin-top:40px;padding-top:22px;border-top:1px solid var(--line);color:var(--faint);font-size:13.5px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px}
#confetti{position:fixed;inset:0;pointer-events:none;z-index:70}

/* skeleton shimmer while a demo loads */
.skel{position:absolute;inset:0;border-radius:inherit;background:linear-gradient(100deg,var(--surface) 30%,#1d1f25 50%,var(--surface) 70%);background-size:200% 100%;animation:shimmer 1.3s linear infinite;z-index:3;transition:opacity .4s}
.ready>.skel,.ready .skel{opacity:0;pointer-events:none}
.static .skel,html:not(.js) .skel{display:none}
@keyframes shimmer{to{background-position:-200% 0}}

@media (max-width:900px){
  .links{display:none}.menu{display:block}.top{gap:12px}
  .page,.phero .grid{grid-template-columns:minmax(0,1fr)}
  .phero .pet{max-width:220px}
  .aside{position:static}
  .bento{grid-template-columns:1fr 1fr}.card,.card.wide{grid-column:span 2}
  .grid3,.steps3{grid-template-columns:1fr}
  .fgrid{grid-template-columns:1fr 1fr}.fabout{grid-column:span 2}
  section{padding:96px 0}
}
@media (max-width:560px){
  .wrap{padding:0 18px}
  .gh{display:none}
  .grid2{grid-template-columns:1fr}
  .bento{grid-template-columns:1fr}.card,.card.wide{grid-column:span 1}
  .btn{padding:12px 18px}
  section{padding:80px 0}
}
@media (prefers-reduced-motion:reduce){
  *,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important;scroll-behavior:auto!important}
  .js .reveal{opacity:1;transform:none}
}
/* ?static: every animation at its final frame, for screenshots */
.static *,.static *::before,.static *::after{animation-duration:0s!important;animation-delay:0s!important;animation-iteration-count:1!important;transition:none!important}
`;

for (const p of pages) {
  p.icon = p.file === "index.html" ? "/img/icon.png?v=__V__" : "/img/icon.png";
  const out = `${SITE}/${p.file}`;
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, render(p));
}

const sm = pages.filter(p => !p.noindex).map(p => `  <url><loc>${ORIGIN}${p.url}</loc><lastmod>${TODAY}</lastmod><changefreq>${p.url === "/" ? "weekly" : "monthly"}</changefreq><priority>${p.priority ?? "0.7"}</priority></url>`).join("\n");
writeFileSync(`${SITE}/sitemap.xml`, `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${sm}\n</urlset>\n`);
console.log("built", pages.map(p => p.file).join(", "));
