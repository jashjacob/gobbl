// Interactive demos, loaded lazily by site.js. Each [data-demo] element is
// initialised when it nears the viewport; in ?static mode each jumps to its
// final state so screenshots show the whole story.
(() => {
const root = document.documentElement;
const STATIC = root.classList.contains("static");
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const INSTANT = STATIC || reduce;
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const sleep = ms => new Promise(r => setTimeout(r, INSTANT ? 0 : ms));
const track = window.track || (() => {});
const { addPet, react, keyTimes, SPECIES, rarity, hsl } = window.Gob;
const onView = (el, fn, threshold = .3) => { const io = new IntersectionObserver(es => { if (es[0].isIntersecting) { io.disconnect(); fn(); } }, { threshold }); io.observe(el); };
const visible = el => { let v = true; new IntersectionObserver(es => v = es[0].isIntersecting, { threshold: .1 }).observe(el); return () => v; };
// Types text into an element one character at a time.
async function typeInto(el, text, speed = 22) {
  if (INSTANT) { el.textContent = text; return; }
  el.textContent = "";
  for (const ch of text) { el.textContent += ch; await new Promise(r => setTimeout(r, speed)); }
}

/* ---------- notch devices ---------- */
const ORDER = ["shelf", "clip", "music", "hud", "cal", "agent", "tools"];
function device(mac, state) {
  const notch = $("[data-notch]", mac), pet = addPet($(".mini", notch), state);
  const tabs = $$(".tabs i", notch);
  return {
    notch, pet,
    show(name) {
      $$(".panel", notch).forEach(p => p.classList.toggle("on", p.dataset.panel === name));
      tabs.forEach((tb, i) => tb.classList.toggle("on", ORDER[i] === name));
      const panel = $(`[data-panel="${name}"]`, notch); if (!panel) return;
      $$(".tile,.row,.lyric", panel).forEach(el => { el.style.animation = "none"; el.offsetHeight; el.style.animation = ""; });
      const a = $(".agent", panel); if (a) a.classList.remove("ok");
    },
    open(v) { notch.classList.toggle("open", v); }
  };
}

const demos = {
  // Hero: a scripted demo that loops while it's on screen.
  hero(mac) {
    const hero = device(mac, { hue: .30, mood: "idle", rest: "idle" });
    const cursor = $(".cursor", mac), flyer = $(".flyer", mac), src = $('[data-f="1"]', mac);
    const isVisible = visible(mac);
    const moveTo = (el, x, y) => el.style.transform = `translate(${x}px,${y}px)`;
    $("[data-notch]", mac).addEventListener("click", () => react(hero.pet, "love", 1600));
    if (INSTANT) { hero.show("shelf"); hero.open(true); return; }
    (async () => {
      await sleep(root.classList.contains("boot") ? 2600 : 1400);
      for (;;) {
        if (!isVisible() || document.hidden) { await sleep(600); continue; }
        const scr = $(".screen", mac).getBoundingClientRect(), f = src.getBoundingClientRect(), n = hero.notch.getBoundingClientRect();
        const fx = f.left - scr.left + 7, fy = f.top - scr.top, nx = n.left - scr.left + n.width / 2 - 20, ny = 8;
        moveTo(cursor, scr.width * .45, scr.height * .75); await sleep(700);
        moveTo(cursor, fx + 22, fy + 26); await sleep(1100);
        cursor.classList.add("click"); flyer.style.transition = "none"; moveTo(flyer, fx, fy); flyer.style.opacity = 1; src.style.opacity = .25; await sleep(250); cursor.classList.remove("click");
        flyer.style.transition = ""; moveTo(flyer, nx, ny + 30); moveTo(cursor, nx + 20, ny + 50);
        await sleep(700); hero.notch.classList.add("drop"); hero.pet.state.open = true; await sleep(500);
        flyer.style.opacity = 0; hero.notch.classList.remove("drop"); hero.pet.state.open = false; react(hero.pet, "eating", 1300);
        await sleep(400); hero.show("shelf"); hero.open(true); src.style.opacity = 1;
        moveTo(cursor, scr.width * .72, scr.height * .6); await sleep(2600);
        hero.show("music"); hero.pet.state.rest = "dance"; hero.pet.state.mood = "dance"; await sleep(3200);
        hero.show("agent"); hero.pet.state.rest = "idle"; react(hero.pet, "alert", 2200); await sleep(1300);
        const go = $('[data-panel="agent"] .pill.go', hero.notch), allow = go.getBoundingClientRect();
        moveTo(cursor, allow.left - scr.left + 18, allow.top - scr.top + 8); await sleep(1100);
        cursor.classList.add("click"); go.classList.add("pressed"); await sleep(200);
        go.classList.remove("pressed"); $('[data-panel="agent"] .agent', hero.notch).classList.add("ok"); cursor.classList.remove("click");
        react(hero.pet, "party", 2200); await sleep(2400);
        hero.open(false); react(hero.pet, "happy", 1500); moveTo(cursor, scr.width * .8, scr.height * .82); await sleep(2800);
      }
    })();
  },

  // Notch basics: the pinned Mac follows the step in view.
  story(el) {
    const story = device($(".mac", el), { hue: .30, mood: "idle", rest: "idle" });
    const steps = $$(".step", el);
    const activate = s => {
      steps.forEach(x => x.classList.toggle("active", x === s));
      story.show(s.dataset.show);
      const m = s.dataset.mood; story.pet.state.rest = m === "dance" ? "dance" : "idle"; react(story.pet, m, m === "dance" ? 1e9 : 1600);
      if (m === "alert") setTimeout(() => { $('[data-panel="agent"] .agent', el).classList.add("ok"); react(story.pet, "party", 2000); }, INSTANT ? 0 : 1600);
    };
    if (STATIC) { steps.forEach(s => s.classList.add("active")); story.show("shelf"); return; }
    const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) activate(e.target); }), { rootMargin: "-45% 0px -45% 0px" });
    steps.forEach(s => io.observe(s));
    activate(steps[0]);
  },

  // A wall of moods, each its own little computer.
  moods(el) {
    $$("canvas", el).forEach(c => {
      const st = JSON.parse(c.dataset.state || "{}"), pet = addPet(c, Object.assign({ hue: .3, char: "retro", rest: st.mood }, st));
      if (st.typing) { // characters appear on its screen as "you" type
        const word = "hello gob"; let i = 0;
        if (INSTANT) { pet.state.text = "hi!"; return; }
        setInterval(() => { i = (i + 1) % (word.length + 6); pet.state.text = word.slice(0, Math.min(i, word.length)); if (i && i <= word.length) { keyTimes.push(performance.now()); while (keyTimes.length > 30) keyTimes.shift(); } }, 180);
      }
    });
  },

  // Agents: a terminal types a Claude Code session and Gob reacts.
  agents(el) {
    const pet = addPet($("canvas", el), { hue: .30, mood: "idle", rest: "idle", char: "retro", hat: "headphones" });
    const term = $("pre", el), status = $(".status", el);
    const setStatus = (text, cls) => { status.textContent = text; status.className = "status " + (cls || ""); };
    const say = html => term.innerHTML = term.innerHTML.replace('<span class="caret"></span>', "") + html + '<span class="caret"></span>';
    async function type(line, speed = 42) {
      for (const ch of line) { say(ch); keyTimes.push(performance.now()); react(pet, "type", 500); await sleep(speed); }
    }
    if (INSTANT) {
      term.innerHTML = '<span class="p">&gt;</span> add dark mode to the settings page\n<span class="d">  Reading src/settings/\n  Editing Theme.swift, SettingsView.swift\n</span><span class="y">  ? Allow Bash: npm test --silent</span>  <span class="d">(answered in the notch)</span>\n<span class="p">  Allowed</span>\n<span class="d">  42 tests passed\n</span><span class="p">  Done.</span> Dark mode is live.\n';
      setStatus("Task done", "ok"); pet.state.mood = pet.state.rest = "work"; return;
    }
    const isVisible = visible(el);
    onView(el, async () => {
      for (;;) {
        if (!isVisible()) { await sleep(800); continue; }
        term.innerHTML = '<span class="caret"></span>'; setStatus("Waiting for a prompt"); pet.state.rest = "idle"; pet.state.mood = "idle";
        say('<span class="p">&gt;</span> '); await type("add dark mode to the settings page");
        say("\n"); await sleep(300); pet.state.until = 0; pet.state.rest = pet.state.mood = "think"; setStatus("Claude is thinking", "work");
        say('<span class="d">  Thinking...\n</span>'); await sleep(1800);
        pet.state.rest = pet.state.mood = "work"; setStatus("Claude is coding", "work");
        say('<span class="d">  Reading src/settings/\n</span>'); await sleep(900);
        say('<span class="d">  Editing Theme.swift, SettingsView.swift\n</span>'); await sleep(1400);
        say('<span class="y">  ? Allow Bash: npm test --silent</span>  <span class="d">(answered in the notch)</span>\n'); react(pet, "alert", 1600); setStatus("Needs you: Allow in the notch", "need"); await sleep(1700);
        say('<span class="p">  Allowed</span>\n'); pet.state.mood = "work"; setStatus("Claude is coding", "work"); await sleep(900);
        say('<span class="d">  42 tests passed\n</span>'); await sleep(700);
        say('<span class="p">  Done.</span> Dark mode is live.\n'); pet.state.rest = "idle"; react(pet, "party", 2600); setStatus("Task done", "ok");
        await sleep(4200);
      }
    }, .4);
  },

  // The Gobbl key: a text field that rewrites itself.
  key(el) {
    const field = $(".kd-text", el), hint = $(".kd-hint", el), vers = $(".kd-vers", el), cap = $(".keycap", el);
    const pet = addPet($("canvas", el), { hue: .3, char: "retro", mood: "idle", rest: "idle" });
    const draft = "hey can we move the call to friday, i have a clash thursday. sorry!!";
    const V = {
      rewrite: ["Tap", "Rewrite", "Hi Priya, could we move our call to Friday? Something came up on Thursday. Sorry for the shuffle!"],
      shorter: ["Double-tap, then Shorter", "Edit mode", "Hi Priya, can we move our call to Friday? Thursday clashes for me."],
      friendlier: ["Double-tap, then Friendlier", "Edit mode", "Hi Priya! Would Friday work for our call instead? Thursday filled up on my end. Thanks so much!"],
      dictate: ["Hold and talk", "Dictation", null],
      ask: ["Type /g and a question", "Ask", null]
    };
    let versions = [draft], busy = false;
    const setVers = () => { vers.innerHTML = versions.map((_, i) => `<i class="${i === versions.length - 1 ? "on" : ""}"></i>`).join("") + `<span>Version ${versions.length}</span>`; };
    const press = async (ms = 260) => { cap.classList.add("down"); await sleep(ms); cap.classList.remove("down"); };
    async function run(kind) {
      if (busy) return; busy = true;
      const [how, label, text] = V[kind];
      $$(".kd-btn", el).forEach(b => b.classList.toggle("on", b.dataset.k === kind));
      hint.textContent = how;
      if (kind === "dictate") {
        cap.classList.add("down"); el.classList.add("listening"); react(pet, "curious", 1600); await sleep(1500); cap.classList.remove("down"); el.classList.remove("listening");
        const add = " I'll send the deck tonight too.";
        const base = field.textContent; if (!INSTANT) for (const ch of add) { field.textContent += ch; await new Promise(r => setTimeout(r, 18)); } else field.textContent = base + add;
        versions.push(field.textContent);
      } else if (kind === "ask") {
        await press(); await typeInto(field, "/g what's 18% of 2,450?", 30); pet.state.mood = "think"; field.classList.add("working"); await sleep(900); field.classList.remove("working");
        field.textContent = "441"; react(pet, "happy", 1200); versions.push("441");
      } else {
        await press(); if (kind !== "rewrite") { await sleep(120); await press(); }
        field.classList.add("working"); pet.state.mood = "think"; await sleep(800); field.classList.remove("working");
        await typeInto(field, text, 14); react(pet, "happy", 1200); versions.push(text);
      }
      hint.textContent = label + " done";
      pet.state.until = pet.state.until || performance.now() + 1; setVers(); busy = false;
      track("demo_key", { action: kind });
    }
    $$(".kd-btn", el).forEach(b => b.addEventListener("click", () => run(b.dataset.k)));
    $(".kd-reset", el).addEventListener("click", () => { if (busy) return; field.textContent = draft; versions = [draft]; setVers(); hint.textContent = "Try a key move"; });
    field.textContent = draft; setVers();
    if (INSTANT) { field.textContent = V.rewrite[2]; versions.push(V.rewrite[2]); setVers(); hint.textContent = "Rewrite done"; return; }
    onView(el, () => setTimeout(() => run("rewrite"), 700), .5);
  },

  // Dictation: a live waveform, then the words at the chosen clean-up level.
  dictate(el) {
    const cv = $("canvas", el), ctx = cv.getContext("2d"), btn = $(".dk-hold", el), out = $(".dk-out", el), meta = $(".dk-meta", el);
    const TEXT = {
      verbatim: "um so I think we should uh ship the update on friday and then like tell the beta testers",
      light: "So I think we should ship the update on Friday and then tell the beta testers.",
      polish: "Let's ship the update on Friday, then tell the beta testers."
    };
    let level = "light", talking = false, amp = 0, said = false;
    const bars = 48, hist = new Array(bars).fill(0);
    function draw(t) {
      const w = cv.width, h = cv.height; ctx.clearRect(0, 0, w, h);
      amp += ((talking ? 1 : 0) - amp) * .12;
      if (!INSTANT) { hist.shift(); hist.push(talking ? (.25 + .75 * Math.abs(Math.sin(t / 90) * Math.sin(t / 37 + 1) + (Math.random() - .5) * .4)) : .03); }
      const bw = w / bars;
      for (let i = 0; i < bars; i++) {
        const v = INSTANT ? .15 + .7 * Math.abs(Math.sin(i * .55) * Math.cos(i * .21)) : hist[i] * (.3 + amp * .7);
        const bh = Math.max(h * .04, v * h * .9);
        ctx.fillStyle = `rgba(166,242,92,${.35 + .65 * (i / bars)})`;
        ctx.beginPath(); ctx.roundRect(i * bw + bw * .2, (h - bh) / 2, bw * .6, bh, bw * .3); ctx.fill();
      }
      if (!INSTANT) requestAnimationFrame(draw);
    }
    requestAnimationFrame(draw);
    const show = () => { out.textContent = TEXT[level]; out.classList.toggle("ai", level === "polish"); meta.textContent = level === "polish" ? "Transcribed on your Mac, then polished by AI (text only, never audio)" : "Transcribed on your Mac in about 0.5 s"; };
    async function finish() {
      talking = false; btn.classList.remove("down"); btn.setAttribute("aria-pressed", "false");
      out.classList.add("working"); out.textContent = "Transcribing on this Mac"; await sleep(500); out.classList.remove("working");
      said = true; if (INSTANT) show(); else { await typeInto(out, TEXT[level], 16); show(); }
    }
    const start = () => { if (talking) return; talking = true; btn.classList.add("down"); btn.setAttribute("aria-pressed", "true"); out.textContent = "Listening"; out.classList.add("working"); meta.textContent = "Your voice stays on this Mac"; track("demo_dictate"); };
    btn.addEventListener("pointerdown", e => { e.preventDefault(); start(); });
    addEventListener("pointerup", () => { if (talking) finish(); });
    btn.addEventListener("keydown", e => { if ((e.key === " " || e.key === "Enter") && !e.repeat) { e.preventDefault(); start(); } });
    btn.addEventListener("keyup", e => { if (e.key === " " || e.key === "Enter") finish(); });
    $$(".dk-seg button", el).forEach(b => b.addEventListener("click", () => {
      $$(".dk-seg button", el).forEach(x => x.setAttribute("aria-pressed", x === b)); level = b.dataset.l; if (said) show();
    }));
    if (INSTANT) { said = true; show(); return; }
    onView(el, async () => { await sleep(500); start(); await sleep(2200); finish(); }, .5);
  },

  // Chat in the notch: a reminder in plain English, a brief, a nudge.
  chat(el) {
    const items = $$(".msg", el);
    if (INSTANT) { items.forEach(m => m.classList.add("in")); return; }
    items.forEach(m => m.classList.remove("in"));
    const isVisible = visible(el);
    onView(el, async () => {
      for (;;) {
        items.forEach(m => m.classList.remove("in"));
        for (const m of items) {
          await sleep(m.classList.contains("me") ? 600 : 1100);
          m.classList.add("in");
          const t = $(".typed", m); if (t) await typeInto(t, t.dataset.text, 28);
        }
        await sleep(6000); while (!isVisible()) await sleep(800);
      }
    }, .4);
  },

  // Memory: a to-do ticks itself off when proof shows up on screen.
  todos(el) {
    const first = $(".todo", el), toast = $(".proof", el), undo = $(".undo", el);
    const tick = () => { first.classList.add("done"); first.querySelector("input").checked = true; };
    const untick = () => { first.classList.remove("done"); first.querySelector("input").checked = false; };
    undo.addEventListener("click", () => { untick(); toast.classList.remove("in"); track("demo_undo"); });
    $$(".todo input", el).forEach(i => i.addEventListener("change", () => i.closest(".todo").classList.toggle("done", i.checked)));
    if (INSTANT) { toast.classList.add("in"); tick(); return; }
    const isVisible = visible(el);
    onView(el, async () => {
      for (;;) {
        untick(); toast.classList.remove("in"); await sleep(1800);
        toast.classList.add("in"); await sleep(1300); tick();
        await sleep(6500); while (!isVisible()) await sleep(800);
      }
    }, .4);
  },

  // Memory: people and projects, hover or focus a node for its card.
  people(el) {
    const card = $(".pcard", el), nodes = $$(".node", el);
    const show = n => {
      nodes.forEach(x => x.classList.toggle("on", x === n));
      card.innerHTML = `<b>${n.dataset.name}</b><span>${n.dataset.role}</span><p>${n.dataset.info}</p>` + (n.dataset.merge ? `<div class="merge"><em>Same person?</em> ${n.dataset.merge}<span class="mb"><button type="button">Merge</button><button type="button">Keep apart</button></span></div>` : "");
      $$(".merge button", card).forEach(b => b.addEventListener("click", () => { $(".merge", card).innerHTML = b.textContent === "Merge" ? "Merged. One card now." : "Kept as two people."; }));
    };
    nodes.forEach(n => { n.addEventListener("pointerenter", () => show(n)); n.addEventListener("focus", () => show(n)); n.addEventListener("click", () => show(n)); });
    show(nodes.find(n => n.dataset.merge) || nodes[0]);
  },

  // Playground: computers, colours, hats, skins, mystery boxes.
  play(el) {
    const play = addPet($("canvas", el), { hue: .30, mood: "idle", rest: "idle", char: "retro", hat: null });
    const stage = $(".stage", el), tag = $(".tag", el);
    stage.addEventListener("click", () => react(play, "love", 1600));
    const species = $(".species", el);
    SPECIES.forEach(([name, hue], i) => {
      const b = document.createElement("button"); b.className = "sw" + (i === 1 ? " on" : ""); b.title = name; b.setAttribute("aria-label", name + " colour"); b.style.background = hsl(hue, 90, 65);
      b.onclick = () => { $$(".sw", species).forEach(x => x.classList.remove("on")); b.classList.add("on"); play.state.hue = hue; delete play.state.top; delete play.state.bottom; play.state.glow = null; play.state.shiny = false; tag.textContent = name; react(play, "happy", 900); };
      species.appendChild(b);
    });
    const hats = $(".hats", el);
    [["none", "None"], ["party", "Party"], ["beanie", "Beanie"], ["headphones", "Headphones"], ["halo", "Halo"], ["crown", "Crown"]].forEach(([k, label], i) => {
      const b = document.createElement("button"); b.className = "chip" + (i === 0 ? " on" : ""); b.textContent = label;
      b.onclick = () => { $$(".chip", hats).forEach(x => x.classList.remove("on")); b.classList.add("on"); play.state.hat = k === "none" ? null : k; react(play, "happy", 900); };
      hats.appendChild(b);
    });
    $$(".charSeg button", el).forEach(b => b.onclick = () => { $$(".charSeg button", el).forEach(x => x.classList.toggle("on", x === b)); play.state.char = b.dataset.c; react(play, "party", 1200); });
    const top = $(".cTop", el), bot = $(".cBot", el), face = $(".cFace", el);
    const skin = () => { play.state.top = top.value; play.state.bottom = bot.value; play.state.glow = face.value === "#a6f25c" ? null : face.value; tag.textContent = "Your skin"; };
    [top, bot, face].forEach(i => i.addEventListener("input", skin));
    $(".saveSkin", el).onclick = () => {
      skin();
      const data = { format: 1, id: "my-gob", name: "My Gob", bodyTop: top.value.toUpperCase(), bodyBottom: bot.value.toUpperCase(), face: "#16161A", glow: face.value.toUpperCase() };
      const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" })); a.download = "My Gob.gobskin"; a.click();
      react(play, "party", 1500);
      track("skin_download");
    };
    $(".hatch", el).onclick = async () => {
      let r = Math.random() * 100, pick = SPECIES[0];
      for (const s of SPECIES) { if (r < s[2]) { pick = s; break; } r -= s[2]; }
      const shiny = Math.random() < .01;
      track("open_box");
      // A random model too: computers ship, they don't hatch.
      const models = { classic: "Classic", retro: "Compact", candy: "Candy" }, char = Object.keys(models)[Math.floor(Math.random() * 3)];
      tag.textContent = "Unboxing"; play.state.boxUntil = performance.now() + 1200; await new Promise(r => setTimeout(r, 1200)); play.state.boxUntil = 0;
      play.state.char = char; $$(".charSeg button", el).forEach(b => b.classList.toggle("on", b.dataset.c === char));
      delete play.state.top; delete play.state.bottom; play.state.glow = null;
      play.state.hue = pick[1]; play.state.shiny = shiny;
      $$(".sw", species).forEach((x, i) => x.classList.toggle("on", SPECIES[i] === pick));
      tag.innerHTML = `It's a ${shiny ? "limited-edition " : ""}${pick[0]} ${models[char]} <span class="rar">${(shiny ? "limited" : rarity(pick[2])).toUpperCase()}</span>`;
      stage.style.setProperty("--stage", hsl(pick[1], 80, 60).replace("hsl", "hsla").replace(")", ",.28)"));
      react(play, "party", 2200);
      const b = stage.getBoundingClientRect(); confetti(b.left + b.width / 2, b.top + b.height / 3);
    };
  },

  // The final call to action: Gob celebrates when you reach it.
  final(el) {
    const fin = addPet($("canvas", el), { hue: .55, mood: "idle", rest: "idle", char: "candy", hat: "party" });
    if (INSTANT) { fin.state.mood = "happy"; return; }
    onView(el, () => react(fin, "party", 2400), .6);
  }
};

/* ---------- confetti ---------- */
let cv, cx, bits = [];
function confetti(x, y, n = 90) {
  if (INSTANT) return;
  if (!cv) { cv = document.createElement("canvas"); cv.id = "confetti"; document.body.appendChild(cv); cx = cv.getContext("2d"); }
  cv.width = innerWidth; cv.height = innerHeight;
  const cs = ["#a6f25c", "#f5c542", "#ff6fa5", "#5b9cf6", "#fff"];
  for (let i = 0; i < n; i++) bits.push({ x, y, vx: (Math.random() - .5) * 14, vy: -Math.random() * 14 - 4, r: Math.random() * 6 + 3, c: cs[i % 5], a: Math.random() * 6, life: 1 });
  if (bits.length === n) requestAnimationFrame(boom);
}
function boom() { cx.clearRect(0, 0, cv.width, cv.height); bits = bits.filter(b => b.life > 0); for (const b of bits) { b.x += b.vx; b.y += b.vy; b.vy += .45; b.a += .2; b.life -= .012; cx.save(); cx.globalAlpha = Math.max(0, b.life); cx.translate(b.x, b.y); cx.rotate(b.a); cx.fillStyle = b.c; cx.fillRect(-b.r / 2, -b.r / 4, b.r, b.r / 2); cx.restore(); } if (bits.length) requestAnimationFrame(boom); else cx.clearRect(0, 0, cv.width, cv.height); }

/* ---------- start each demo as it nears the viewport ---------- */
const start = el => { if (el.dataset.ready) return; el.dataset.ready = "1"; try { demos[el.dataset.demo]?.(el); } catch (e) { console.error(e); } el.classList.add("ready"); };
const all = $$("[data-demo]");
if (STATIC) all.forEach(start);
else {
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { io.unobserve(e.target); start(e.target); } }), { rootMargin: "400px 0px" });
  all.forEach(el => io.observe(el));
}
})();
