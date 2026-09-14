// The home page: hero demo, feature tour, comparison, FAQ.
import { ic, GH, MCP_LIVE, mcpBadge, cmpTable, CMP_NOTE, HOME_FAQ, faqHTML, faqLD, orgLD, websiteLD, appLD, DICTATE_DEMO, TODOS_DEMO, PEOPLE_DEMO, MEMCHAT, DEMO_CSS } from "./data.mjs";

const panels = `
<div class="panel" data-panel="shelf"><div class="tile-row"><div class="tile" style="--i:0"><div class="sq" style="--c:linear-gradient(#ff8b7f,#e0443b)"></div>Pitch.pdf</div><div class="tile" style="--i:1"><div class="sq" style="--c:linear-gradient(#8fb8ff,#3b82f6)"></div>Shot.png</div><div class="tile" style="--i:2"><div class="sq" style="--c:linear-gradient(#ffe08a,#f59e0b)"></div>Notes.zip</div></div></div>
<div class="panel" data-panel="clip"><div class="clip"><div class="search">${ic("search")}Search clipboard</div><div class="row" style="--i:0"><i style="--c:#5b9cf6"></i>https://gobbl.xeve.io</div><div class="row" style="--i:1"><i style="--c:#a6f25c"></i>Meeting notes: ship Friday</div><div class="row" style="--i:2"><i style="--c:#ff6fa5"></i>#FF6FA5</div></div></div>
<div class="panel" data-panel="music"><div class="music"><div class="art"></div><div style="flex:1;min-width:0"><b>Night Drive</b><small>Now playing</small><div class="bar"><i></i></div><div class="lyric">and the city hums along</div></div><div class="eq"><i style="--i:0"></i><i style="--i:1"></i><i style="--i:2"></i><i style="--i:3"></i></div></div></div>
<div class="panel" data-panel="hud"><div class="hud"><div class="hrow">${ic("speaker")}<div class="hbar"><i style="--v:.62"></i></div><em>62</em></div><div class="hrow">${ic("sun")}<div class="hbar"><i style="--v:.8"></i></div><em>80</em></div><div class="hrow caps">${ic("keyboard")}<span>Caps Lock is on</span></div></div></div>
<div class="panel" data-panel="cal"><div class="cal"><div><small>In 5 min, 10:30</small><b>Design review</b><span>Google Meet, 4 people</span></div><span class="pill go">Join</span></div></div>
<div class="panel" data-panel="agent"><div class="agent"><b>Claude Code wants to run a command</b><code>npm test --silent</code><div class="btns"><span class="pill go">Allow</span><span class="pill">Deny</span><span class="pill">Ask in terminal</span></div><div class="okmsg">Allowed. Tests pass.</div></div></div>
<div class="panel" data-panel="tools"><div class="tools"><div class="big">25:00<small>Focus</small></div><div>${ic("bolt")}Awake</div><div>${ic("mic")}Mute</div><div>${ic("drop")}Color</div><div>${ic("scan")}Screen text</div></div></div>`;
const tabs = `<div class="tabs"><i class="on"></i><i></i><i></i><i></i><i></i><i></i><i></i></div>`;

const heroMac = `<div class="mac" data-demo="hero" role="img" aria-label="Animated demo: a file is dragged onto the MacBook notch, the pet eats it, then the notch shows music and a Claude Code permission request.">
  <div class="screen">
    <div class="menubar"><div><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span></div><div>Mon 9:41</div></div>
    <div class="desk-icons"><div class="file" data-f="1"><div class="doc" data-ext="PDF"></div>Pitch.pdf</div><div class="file"><div class="doc" data-ext="PNG" style="--c:#3b82f6"></div>Shot.png</div></div>
    <div class="notch" data-notch><canvas class="mini" width="240" height="240"></canvas><div class="wing"><span class="eq"><i style="--i:0"></i><i style="--i:1"></i><i style="--i:2"></i></span></div>${tabs}${panels}</div>
    <div class="flyer"><div class="file"><div class="doc" data-ext="PDF"></div></div></div>
    <svg class="cursor" viewBox="0 0 24 24"><path d="M4 2l15 8.5-6.6 1.4L16 20l-2.7 1.2-3.5-8L5 17z" fill="#fff" stroke="#000" stroke-width="1.2"/></svg>
  </div>
</div>`;
const storyMac = `<div class="mac" role="img" aria-label="The Gobbl notch, expanded, showing the panel for the feature described alongside.">
  <div class="screen"><div class="menubar"><div><b>Gobbl</b></div><div>9:41</div></div>
    <div class="notch open" data-notch><canvas class="mini" width="240" height="240"></canvas>${tabs}${panels.replace('data-panel="shelf"', 'data-panel="shelf" data-first')}</div>
  </div>
</div>`.replace('class="panel" data-panel="shelf" data-first', 'class="panel on" data-panel="shelf"');

const step = (show, mood, icon, n, h, p) => `<div class="step" data-show="${show}" data-mood="${mood}"><div class="n">${ic(icon)}${n}</div><h3>${h}</h3><p>${p}</p></div>`;

const MOODS = [
  ["idle", "Watches your cursor", {}], ["eating", "Eats the files you drop", { mood: "eating" }], ["dance", "Dances to your music", { mood: "dance", char: "candy", hue: .93 }],
  ["work", "Matrix rain while your agent codes", { mood: "work", char: "classic" }], ["think", "Thinking face while it plans", { mood: "think", hue: .55 }], ["type", "Types along with you", { mood: "type", typing: true, char: "classic", hue: .13 }],
  ["love", "Loves a pat", { mood: "love", char: "candy", hue: .78 }], ["sleep", "Naps when you step away", { mood: "sleep", hue: .48 }], ["party", "Celebrates when a task is done", { mood: "party", hat: "party", char: "candy", hue: .3 }]
];
const moodGrid = `<div class="moods" data-demo="moods">${MOODS.map(([k, label, st], i) => `<figure class="mood reveal" style="--i:${i % 3}"><canvas width="240" height="240" data-state='${JSON.stringify(Object.assign({ mood: k === "idle" ? "idle" : k }, st))}' role="img" aria-label="Gob ${label.toLowerCase()}"></canvas><figcaption>${label}</figcaption></figure>`).join("")}</div>`;

const MCP_CLIENTS = ["Claude Code", "Claude Desktop", "Codex / ChatGPT", "Cursor", "VS Code", "Windsurf", "Gemini CLI", "LM Studio", "Zed"];
const MCP_TOOLS = ["search_memory", "get_day", "list_todos", "who_is", "get_person", "get_project", "recent_activity", "get_clipboard", "add_reminder", "mark_todo_done"];

export const home = {
  file: "index.html", url: "/", priority: "1.0", boot: true,
  title: "Gobbl: the free notch app for Mac, with a pet",
  ogTitle: "Gobbl: your notch has a pet",
  desc: "Gobbl is a free, open-source notch app for Mac: file shelf, clipboard, music, on-device Whisper dictation, AI writing anywhere, Claude Code approvals and a pet.",
  ld: [orgLD, websiteLD, appLD, faqLD(HOME_FAQ)],
  body: `
<section class="hero">
  <div class="glow" aria-hidden="true"></div>
  <div class="wrap">
    <p class="eyebrow"><i></i>The free, open-source notch app for Mac</p>
    <h1><span class="w" style="--i:0">Your</span> <span class="w" style="--i:1">notch</span> <span class="w" style="--i:2">has</span> <span class="w grad" style="--i:3">a</span> <span class="w grad" style="--i:4">pet.</span></h1>
    <p class="lede">Gobbl moves Gob, a tiny retro computer, into your MacBook's notch. It holds your files and clipboard, plays your music, writes and takes dictation in any app, and cheers on Claude Code. If you want, it remembers what you were doing, too.</p>
    <div class="cta hero-cta">
      <a class="btn primary magnetic" href="/download">${ic("download")}Download for Mac <small data-version>&middot; coming soon</small></a>
      <a class="btn ghost magnetic" href="${GH}">${ic("github")}Star on GitHub</a>
    </div>
    <p class="fine">macOS 14+ &middot; MIT licensed &middot; no account &middot; near-zero CPU at rest</p>
    ${heroMac}
  </div>
</section>

<div class="marquee" aria-label="Works with the apps you already use"><div class="track">
  <span>Claude Code</span><span>Codex</span><span>Spotify</span><span>Apple Music</span><span>YouTube in Chrome</span><span>Google Meet</span><span>Zoom</span><span>Slack</span><span>Mail</span><span>Messages</span><span>Notion</span><span>VS Code</span><span>Cursor</span><span>Xcode</span><span>Safari</span><span>Figma</span>
</div></div>

<nav class="fnav" aria-label="Feature sections"><div>
  <a href="#notch">Notch</a><a href="#pet">Pet</a><a href="#agents">AI agents</a><a href="#key">Gobbl key</a><a href="#dictation">Dictation</a><a href="#chat">Chat</a><a href="#memory">Memory</a><a href="#mcp">MCP</a><a href="#privacy">Privacy</a><a href="#compare">Compare</a>
</div></nav>

<section id="notch">
  <div class="wrap">
    <div class="kicker reveal">${ic("tray")}Notch basics</div>
    <h2 class="reveal" style="--i:1">The notch app for Mac<br>that does the little things.</h2>
    <p class="sub reveal" style="--i:2">Hover the notch or drop something on it and it opens into a small panel. Everything below lives there, one gesture away from any app.</p>
    <div class="story" data-demo="story">
      <div class="sticky">${storyMac}</div>
      <div class="steps">
        ${step("shelf", "eating", "tray", "01 &middot; Shelf", "Drop it on the notch. Gob eats it.", "Park files in the notch and drag them out anywhere, or AirDrop and share them. Right-click to convert or compress images, PDFs and videos, remove a background, copy the text or zip. All on your Mac.")}
        ${step("clip", "curious", "clipboard", "02 &middot; Clipboard", "Everything you copied, on ⇧⌘Space.", "A searchable clipboard history with pins. Items from password managers are never saved.")}
        ${step("music", "dance", "music", "03 &middot; Now Playing", "Music from any app, with lyrics.", "Spotify, Apple Music, YouTube in Chrome: artwork, controls, synced lyrics and an output picker. Gob dances along.")}
        ${step("hud", "curious", "speaker", "04 &middot; HUDs", "Volume, brightness and Caps Lock, quietly.", "Optional notch-sized replacements for the big system pop-ups, plus charging and low-battery notices.")}
        ${step("cal", "happy", "calendar", "05 &middot; Calendar", "Your next meeting, with a Join button.", "One click into Meet or Zoom, and a gentle nudge from Gob five minutes before.")}
        ${step("tools", "happy", "timer", "06 &middot; Quick tools", "Focus timer, keep-awake and more.", "A focus timer, keep-awake, mic mute, a colour picker and copy-text-from-screen, one click each.")}
      </div>
    </div>
  </div>
</section>

<section id="pet" class="band">
  <div class="wrap">
    <div class="kicker reveal">${ic("heart")}The pet</div>
    <h2 class="reveal" style="--i:1">Gob reacts to what you do.</h2>
    <p class="sub reveal" style="--i:2">Its eyes follow your cursor. It types along with you, letters appearing on its little screen. When your AI agent is coding, its screen fills with Matrix rain. Try typing on this page.</p>
    ${moodGrid}
    <div class="play" data-demo="play">
      <div class="stage reveal"><div class="skel"></div><p class="hint">Click to pet it &middot; move your mouse</p><canvas width="680" height="680" role="img" aria-label="Your Gob: pick a model, colour and hat"></canvas><p class="tag" aria-live="polite">Sprout</p></div>
      <div class="controls reveal" style="--i:1">
        <h3>Every Gobbl ships different.</h3>
        <p class="muted">A late-70s Classic, a mid-80s Compact or a late-90s Candy. It arrives in a box in one of eight colours, and 1 in 100 ship as a limited edition. Keep a daily streak to level up and earn 11 hats, 4 of them seasonal.</p>
        <div class="ctl"><p class="fh">Model</p><div class="seg charSeg" role="group" aria-label="Model"><button type="button" data-c="classic">Classic ’77</button><button type="button" class="on" data-c="retro">Compact ’84</button><button type="button" data-c="candy">Candy ’98</button></div></div>
        <div class="ctl"><p class="fh">Colour</p><div class="chips species"></div></div>
        <div class="ctl"><p class="fh">Hat</p><div class="chips hats"></div></div>
        <div class="ctl"><p class="fh">Design a skin</p><div class="colors"><label><input type="color" class="cTop" value="#b8f28a">Top</label><label><input type="color" class="cBot" value="#5bb84a">Bottom</label><label><input type="color" class="cFace" value="#a6f25c">Glow</label><button type="button" class="btn ghost small saveSkin">${ic("download")}Download .gobskin</button></div></div>
        <div class="ctl"><button type="button" class="btn primary magnetic hatch">${ic("box")}Open a mystery box</button></div>
      </div>
    </div>
  </div>
</section>

<section id="agents">
  <div class="wrap">
    <div class="kicker reveal">${ic("terminal")}AI agents in your notch</div>
    <h2 class="reveal" style="--i:1">Approve Claude Code<br>without switching windows.</h2>
    <p class="sub reveal" style="--i:2">Connect Claude Code or Codex in one click. Gob thinks while the agent plans, codes along with Matrix rain, and waves when it needs you. Claude Code's permission requests show up in the notch with Allow and Deny.</p>
    <div class="agents" data-demo="agents">
      <div class="term reveal"><div class="skel"></div><div class="tbar"><i></i><i></i><i></i><span>claude</span></div><pre aria-label="Example Claude Code session"><span class="p">&gt;</span> add dark mode to the settings page</pre></div>
      <div class="agent-pet reveal" style="--i:1"><canvas width="440" height="440" role="img" aria-label="Gob reacting to the coding agent"></canvas><p class="status" aria-live="polite">Waiting for a prompt</p></div>
    </div>
    <p class="note">If Gobbl isn't running, or you don't answer within 30 seconds, Claude asks in the terminal as usual. Codex gets status and celebrations; Allow and Deny are for Claude Code.</p>
  </div>
</section>

<section id="key" class="band">
  <div class="wrap">
    <div class="kicker reveal">${ic("keyboard")}Write anywhere</div>
    <h2 class="reveal" style="--i:1">One key that writes<br>in every app.</h2>
    <p class="sub reveal" style="--i:2">The right Option key becomes the Gobbl key. It works in any text field: Mail, Slack, Notion, a browser form. Try it on the draft below.</p>
    <div class="kd" data-demo="key">
      <div class="kd-win reveal" role="group" aria-label="Demo: an email draft the Gobbl key rewrites">
        <div class="skel"></div>
        <div class="kd-head"><i></i><i></i><i></i><span>New message</span></div>
        <div class="kd-row"><span>To</span>Priya Shah</div>
        <div class="kd-row"><span>Subject</span>Our call this week</div>
        <div class="kd-text" aria-live="polite">hey can we move the call to friday, i have a clash thursday. sorry!!</div>
        <div class="kd-foot"><span class="kd-hint">Try a key move</span><span class="kd-vers"></span></div>
      </div>
      <div class="kd-side reveal" style="--i:1">
        <div class="kd-top"><canvas width="240" height="240" aria-hidden="true"></canvas><div class="keycap" aria-hidden="true"><span>⌥</span><small>right option</small></div></div>
        <div class="kd-btns">
          <button type="button" class="kd-btn" data-k="rewrite"><b>Tap</b><span>Write or rewrite</span></button>
          <button type="button" class="kd-btn" data-k="shorter"><b>Double-tap</b><span>Edit mode: shorter</span></button>
          <button type="button" class="kd-btn" data-k="friendlier"><b>Double-tap</b><span>Edit mode: friendlier</span></button>
          <button type="button" class="kd-btn" data-k="dictate"><b>Hold</b><span>Dictate</span></button>
          <button type="button" class="kd-btn" data-k="ask"><b>/g</b><span>Ask a question</span></button>
          <button type="button" class="kd-reset">Reset</button>
        </div>
      </div>
    </div>
  </div>
</section>

<section id="dictation">
  <div class="wrap">
    <div class="kicker reveal">${ic("mic")}Dictation</div>
    <h2 class="reveal" style="--i:1">Dictation that never<br>leaves your Mac.</h2>
    <p class="sub reveal" style="--i:2">Hold the Gobbl key and talk. Whisper runs on your Mac, so your voice stays there, and there's no word cap and no account. A free, on-device alternative to cloud dictation apps.</p>
    ${DICTATE_DEMO}
    <div class="stats">
      <div class="stat reveal"><b data-count="0.5" data-dec="1" data-prefix="~" data-suffix=" s">~0.5 s</b><span>per sentence on Apple silicon</span></div>
      <div class="stat reveal" style="--i:1"><b>On-device</b><span>your voice never leaves the Mac</span></div>
      <div class="stat reveal" style="--i:2"><b data-count="0">0</b><span>word caps, accounts or fees</span></div>
      <div class="stat reveal" style="--i:3"><b data-count="3">3</b><span>clean-up levels, from verbatim to polished</span></div>
    </div>
    <p class="chipsline reveal">Custom words for names and jargon &middot; language lock &middot; hands-free mode &middot; three Whisper models</p>
    <a class="more" href="/dictation">Everything about offline dictation on Mac${ic("arrow")}</a>
  </div>
</section>

<section id="chat" class="band">
  <div class="wrap split">
    <div>
      <div class="kicker reveal">${ic("chat")}Chat in the notch</div>
      <h2 class="reveal" style="--i:1">Ask your notch.<br>It remembers for you.</h2>
      <p class="sub reveal" style="--i:2">Set reminders in plain English, like "remind me every weekday at 10". Get a morning brief and an evening wrap of your day. Gob nudges you gently, never more than three times a day, and stays quiet while you focus.</p>
      <ul class="ticks reveal" style="--i:3"><li>${ic("bell")}Reminders, one-off or repeating</li><li>${ic("sun")}Morning brief with meetings and to-dos</li><li>${ic("moon")}Evening wrap of what got done</li><li>${ic("calendar")}A brief 10 minutes before meetings with people Gobbl knows</li><li>${ic("heart")}At most 3 nudges a day, inside your active hours</li></ul>
    </div>
    <div class="chatbox reveal" style="--i:1" data-demo="chat">
      <div class="chat-top"><canvas width="96" height="96" data-gob='{"char":"retro","mood":"happy","rest":"happy"}' aria-hidden="true"></canvas><b>Gob</b><span>in your notch</span></div>
      <div class="msg me in"><span class="typed" data-text="remind me every weekday at 10 to post standup">remind me every weekday at 10 to post standup</span></div>
      <div class="msg gob in">Done. Every weekday at 10:00 AM: post standup.</div>
      <div class="msg brief in"><b>${ic("sun")}Morning brief</b>Three meetings today, the first at 11:00. The Studio North invoice is due Friday.</div>
      <div class="msg nudge in">Gentle nudge: you said you'd send Priya the deck.</div>
    </div>
  </div>
</section>

<section id="memory">
  <div class="wrap">
    <div class="kicker reveal">${ic("brain")}Memory <span class="badge">Beta &middot; opt-in</span></div>
    <h2 class="reveal" style="--i:1">AI memory for your Mac<br>that finishes your to-dos.</h2>
    <p class="sub reveal" style="--i:2">Turn Memory on and Gobbl reads the text on your screen, never screenshots, and keeps it on your Mac. It finds the things you said you'd do, with the source and the reason, and ticks them off when proof shows up, like a "Payment successful" page. With Undo, of course.</p>
    <div class="mem-grid">
      ${TODOS_DEMO}
      ${MEMCHAT}
    </div>
    <h3 class="h3 reveal">Who is who, built from your screen.</h3>
    <p class="sub reveal">People, projects, organisations and topics get their own cards in the Memory window, next to your to-dos and a day-by-day timeline with digests. When two names look like one person, Gobbl asks "Same person?" instead of guessing. Search by meaning runs on your Mac, and the memory chat cites where each answer came from.</p>
    ${PEOPLE_DEMO}
    <ul class="ticks cols reveal"><li>${ic("eyeoff")}Skips password fields, private windows and banking sites</li><li>${ic("lock")}Masks card numbers, keys, passwords and one-time codes</li><li>${ic("pause")}Pause, forget the last hour, forget an app, or forget it all</li><li>${ic("eye")}A small indicator in the notch whenever it's on</li></ul>
    <a class="more" href="/memory">How screen memory works, and what it never reads${ic("arrow")}</a>
  </div>
</section>

<section id="mcp" class="band">
  <div class="wrap mcp">
    <div>
      <div class="kicker reveal">${ic("plug")}MCP connector${mcpBadge}</div>
      <h2 class="reveal" style="--i:1">Your memory,<br>in every AI app.</h2>
      <p class="sub reveal" style="--i:2">One switch connects what Gobbl remembers to Claude Code, Claude Desktop, Codex and the ChatGPT desktop app, Cursor, VS Code, Windsurf, Gemini CLI, LM Studio and Zed, through the Model Context Protocol. Your AI apps can search your memory, look up people and projects, read your day and your to-dos, and ask Gobbl to add a reminder or tick a to-do off.</p>
    </div>
    <div class="mcp-card reveal" style="--i:1">
      <div class="switch-row"><span>${ic("plug")}Connect memory to AI apps</span><span class="switch" aria-hidden="true"><i></i></span></div>
      <div class="clients">${MCP_CLIENTS.map((c, i) => `<span style="--i:${i}">${c}</span>`).join("")}</div>
      <div class="tools-list">${MCP_TOOLS.map(t => `<code>${t}</code>`).join("")}</div>
      <p>Answers cite their source, like "WhatsApp &middot; Samar &middot; Today 7:22 PM". Your memory stays on your Mac, and each call is logged there by tool name and time only. Any other MCP app can use the copyable command.</p>
    </div>
  </div>
</section>

<section id="privacy">
  <div class="wrap">
    <div class="kicker reveal">${ic("shield")}Privacy</div>
    <h2 class="reveal" style="--i:1">Local first. And you can check.</h2>
    <p class="sub reveal" style="--i:2">Gobbl does as much as it can on your Mac. When an AI feature needs a model, you can see exactly what was sent.</p>
    <div class="bento">
      <div class="card wide reveal"><div class="ico">${ic("monitor")}</div><h3>On your Mac</h3><p>Shelf, clipboard, music, dictation audio, the pet and everything Memory stores never leave your Mac.</p></div>
      <div class="card wide reveal" style="--i:1"><div class="ico">${ic("shield")}</div><h3>A provider that keeps nothing</h3><p>AI requests go through Xeve's service to a model provider that doesn't keep or train on your data.</p></div>
      <div class="card wide reveal" style="--i:2"><div class="ico">${ic("log")}</div><h3>A log of everything sent</h3><p>Every AI request is logged on your Mac, so you can see exactly what left it and when.</p></div>
      <div class="card wide reveal" style="--i:3"><div class="ico">${ic("github")}</div><h3>Open source</h3><p>Every line is on GitHub under the MIT license. No analytics in the app, and no account.</p></div>
    </div>
    <a class="more" href="/privacy">Read the plain-English privacy page${ic("arrow")}</a>
  </div>
</section>

<section id="more" class="band">
  <div class="wrap">
    <div class="kicker reveal">${ic("layers")}And a lot more</div>
    <h2 class="reveal" style="--i:1">The rest of the toolkit.</h2>
    <div class="bento">
      <div class="card reveal"><div class="ico">${ic("wand")}</div><h3>File tools</h3><p>Convert, compress, remove backgrounds, copy text or zip, right from the shelf.</p></div>
      <div class="card reveal" style="--i:1"><div class="ico">${ic("basket")}</div><h3>Shake to drop</h3><p>Shake while dragging a file and a drop basket appears under your pointer.</p></div>
      <div class="card reveal" style="--i:2"><div class="ico">${ic("film")}</div><h3>Clips in one click</h3><p>Render a 6-second MP4 and GIF of your pet, or record your real notch.</p></div>
      <div class="card reveal"><div class="ico">${ic("monitor")}</div><h3>Every screen</h3><p>A pill on Macs without a notch and on external displays. Hides for full-screen apps.</p></div>
      <div class="card reveal" style="--i:1"><div class="ico">${ic("hat")}</div><h3>Streaks, levels, hats</h3><p>Keep your streak, level up, unlock 11 hats, including Halloween, Diwali and December ones.</p></div>
      <div class="card reveal" style="--i:2"><div class="ico">${ic("cpu")}</div><h3>Near-zero CPU</h3><p>At rest Gob only redraws to blink. Nothing heavy runs in the background.</p></div>
    </div>
    <a class="more" href="/features">See every feature${ic("arrow")}</a>
  </div>
</section>

<section id="compare">
  <div class="wrap">
    <div class="kicker reveal">${ic("list")}Compare</div>
    <h2 class="reveal" style="--i:1">One free app instead of three.</h2>
    <p class="sub reveal" style="--i:2">Gobbl overlaps with notch apps, dictation apps and memory apps. Here's an honest look at how it lines up. Each of these tools does something well; Gobbl's bet is putting them together, free and open source.</p>
    <div class="reveal">${cmpTable(["gobbl", "droppy", "notchnook", "boring", "alcove", "wispr", "superwhisper", "goldfish", "screenpipe"], "Gobbl compared with notch, dictation and memory apps for Mac")}</div>
    ${CMP_NOTE}
    <div class="cmp-links">
      <a href="/compare/wispr-flow">Gobbl vs Wispr Flow${ic("arrow")}</a><a href="/compare/droppy">Gobbl vs Droppy${ic("arrow")}</a><a href="/compare/notchnook">Gobbl vs NotchNook${ic("arrow")}</a><a href="/compare/goldfish">Gobbl vs Goldfish${ic("arrow")}</a>
    </div>
  </div>
</section>

<section id="faq" class="faq band">
  <div class="wrap narrow">
    <h2 class="reveal">Questions</h2>
    ${faqHTML(HOME_FAQ)}
    <a class="more" href="/faq">All questions${ic("arrow")}</a>
  </div>
</section>

<section class="final" data-demo="final">
  <div class="wrap">
    <canvas width="340" height="340" class="reveal" role="img" aria-label="A candy-coloured Gob wearing a party hat"></canvas>
    <h2 class="reveal" style="--i:1">Give your notch<br>something to do.</h2>
    <div class="cta reveal" style="--i:2">
      <a class="btn primary magnetic" href="/download">${ic("download")}Download for Mac <small>&middot; coming soon</small></a>
      <a class="btn ghost magnetic" href="${GH}">${ic("github")}Star on GitHub</a>
    </div>
  </div>
</section>`,
  css: DEMO_CSS + `
.band{background:linear-gradient(180deg,transparent,var(--bg2) 12%,var(--bg2) 88%,transparent)}
.muted{color:var(--muted)}
.narrow{max-width:860px}
.glow{position:absolute;left:50%;top:40px;width:760px;height:520px;margin-left:-380px;border-radius:50%;background:#a6f25c;opacity:.09;filter:blur(110px);pointer-events:none;animation:drift 24s ease-in-out infinite alternate}
@keyframes drift{to{transform:translate(30px,-20px) scale(1.06)}}
.hero{position:relative;padding:140px 0 70px;text-align:center;overflow:hidden}
.eyebrow{display:inline-flex;gap:8px;align-items:center;font-size:13.5px;font-weight:650;color:var(--lime);padding:6px 13px;border-radius:999px;background:rgba(166,242,92,.08);border:1px solid rgba(166,242,92,.2);margin:0 0 22px}
.eyebrow i{width:7px;height:7px;border-radius:50%;background:var(--lime);box-shadow:0 0 12px var(--lime);animation:pulse 1.6s infinite}
@keyframes pulse{50%{opacity:.3}}
.hero h1{font-size:clamp(50px,8.6vw,108px);line-height:.95;letter-spacing:-.045em;margin:0 0 22px;font-weight:850}
.hero h1 .w{display:inline-block;transform:translateY(.3em);filter:blur(6px);animation:rise .9s var(--ease) forwards;animation-delay:calc(var(--i)*80ms + 100ms)}
.boot .hero h1 .w{animation-delay:calc(var(--i)*80ms + 1500ms)}
.hero h1 .grad{background:linear-gradient(100deg,var(--lime),#d9f7b8);-webkit-background-clip:text;background-clip:text;color:transparent}
@keyframes rise{to{opacity:1;transform:none;filter:none}}
.hero .lede{font-size:clamp(17px,1.9vw,20px);color:var(--muted);max-width:680px;margin:0 auto 32px;text-wrap:pretty}
.hero-cta{justify-content:center}
.fine{margin:14px 0 0;font-size:13.5px;color:var(--faint)}
.mac{position:relative;margin:60px auto 0;width:min(980px,100%);aspect-ratio:16/9.2;border-radius:26px 26px 10px 10px;padding:14px 14px 0;background:linear-gradient(#2b2e35,#1b1d22);box-shadow:0 60px 120px -40px rgba(0,0,0,.9),0 0 0 1px rgba(255,255,255,.07) inset}
.hero .mac{opacity:0;transform:perspective(1600px) rotateX(18deg) translateY(60px) scale(.94);animation:macIn 1.4s var(--ease) .5s forwards}
.boot .hero .mac{animation-delay:1.9s}
@keyframes macIn{to{opacity:1;transform:perspective(1600px) rotateX(0) translateY(0) scale(1)}}
.mac::after{content:"";position:absolute;left:-7%;right:-7%;bottom:-18px;height:18px;border-radius:0 0 30px 30px;background:linear-gradient(#c5c8ce,#8b8f97);box-shadow:0 20px 40px rgba(0,0,0,.6)}
.screen{position:relative;height:100%;border-radius:14px 14px 0 0;overflow:hidden;background:radial-gradient(120% 90% at 20% 110%,#ff6fa5 0%,transparent 45%),radial-gradient(110% 90% at 90% 100%,#5b9cf6 0%,transparent 50%),linear-gradient(160deg,#2b2350,#141527 60%,#0d0e18)}
.menubar{position:absolute;top:0;left:0;right:0;height:30px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font-size:12.5px;color:rgba(255,255,255,.85);background:rgba(10,10,20,.25)}
.menubar b{margin-right:16px}.menubar span{margin-right:16px;opacity:.85}
.desk-icons{position:absolute;right:26px;top:60px;display:grid;gap:18px;justify-items:center}
.file{width:54px;text-align:center;font-size:10.5px;color:#fff;text-shadow:0 1px 3px #000}
.file .doc{width:40px;height:50px;margin:0 auto 5px;border-radius:5px;position:relative;background:linear-gradient(#fff,#dfe3ea);box-shadow:0 4px 10px rgba(0,0,0,.35)}
.file .doc::after{content:attr(data-ext);position:absolute;bottom:6px;left:0;right:0;font-size:8.5px;font-weight:800;color:var(--c,#e0443b)}
.flyer{position:absolute;left:0;top:0;z-index:5;opacity:0;transition:transform 1.1s var(--ease),opacity .4s;pointer-events:none}
.cursor{position:absolute;z-index:9;width:22px;height:22px;left:0;top:0;transform:translate(560px,330px);transition:transform 1s var(--ease);pointer-events:none;filter:drop-shadow(0 2px 3px rgba(0,0,0,.6))}
.cursor.click{animation:click .3s}
@keyframes click{50%{scale:.8}}
.notch{position:absolute;top:0;left:50%;translate:-50% 0;z-index:4;width:250px;height:30px;background:#000;border-radius:0 0 16px 16px;transition:width .55s var(--spring),height .55s var(--spring),border-radius .4s var(--ease),box-shadow .4s;overflow:hidden;cursor:pointer}
.notch.open{width:min(600px,86%);height:clamp(170px,40%,235px);border-radius:0 0 30px 30px;box-shadow:0 30px 60px -10px rgba(0,0,0,.7)}
.notch.drop{box-shadow:0 0 0 2px var(--lime),0 0 40px rgba(166,242,92,.35)}
.notch .mini{position:absolute;left:14px;top:3px;width:24px;height:24px;transition:left .5s var(--spring),top .5s var(--spring),width .5s var(--spring),height .5s var(--spring)}
.notch.open .mini{left:22px;top:46px;width:min(120px,22%);height:auto;aspect-ratio:1}
.notch .wing{position:absolute;right:16px;top:8px;transition:opacity .2s}
.notch.open .wing{opacity:0}
.tabs{position:absolute;left:20px;top:8px;display:flex;gap:6px;opacity:0;transition:opacity .3s .15s}
.notch.open .tabs{opacity:1}
.tabs i{width:20px;height:14px;border-radius:7px;background:rgba(255,255,255,.1)}.tabs i.on{background:rgba(255,255,255,.3)}
.panel{position:absolute;left:calc(min(120px,22%) + 44px);right:18px;top:44px;bottom:16px;opacity:0;transform:translateY(12px);transition:opacity .35s,transform .45s var(--ease);pointer-events:none;text-align:left;font-size:12px;color:#dfe2e6}
.notch.open .panel.on{opacity:1;transform:none;transition-delay:.12s}
.tile-row{display:flex;gap:8px;height:100%}
.tile{flex:1;border-radius:14px;background:rgba(255,255,255,.07);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;font-size:10.5px;animation:pop .5s var(--spring) both;animation-delay:calc(var(--i)*80ms)}
.tile .sq{width:34px;height:40px;border-radius:6px;background:var(--c)}
@keyframes pop{from{transform:scale(.6);opacity:0}}
.music{display:flex;gap:12px;height:100%;align-items:center;background:rgba(255,255,255,.06);border-radius:14px;padding:10px}
.art{width:64px;height:64px;border-radius:10px;background:conic-gradient(from 30deg,#ff6fa5,#5b9cf6,#a6f25c,#ff6fa5);animation:hue 8s linear infinite;flex:none}
@keyframes hue{to{filter:hue-rotate(360deg)}}
.music b{display:block;font-size:13px;color:#fff}.music small{color:var(--muted)}
.bar{height:3px;border-radius:3px;background:rgba(255,255,255,.14);margin:7px 0 6px;overflow:hidden}
.bar i{display:block;height:100%;width:30%;background:#fff;animation:prog 9s linear infinite}
@keyframes prog{to{width:100%}}
.lyric{font-size:11.5px;color:var(--lime);font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;animation:pop .5s var(--ease) both}
.eq{display:flex;gap:3px;align-items:flex-end;height:14px}
.eq i{width:3px;background:var(--lime);border-radius:2px;animation:eq .8s ease-in-out infinite alternate;animation-delay:calc(var(--i)*-.2s)}
@keyframes eq{from{height:3px}to{height:14px}}
.hud{display:flex;flex-direction:column;justify-content:center;gap:10px;height:100%;padding:0 6px}
.hrow{display:flex;gap:10px;align-items:center}.hrow .i{width:16px;height:16px;color:#fff}
.hbar{flex:1;height:6px;border-radius:6px;background:rgba(255,255,255,.14);overflow:hidden}
.hbar i{display:block;height:100%;width:calc(var(--v)*100%);background:#fff;border-radius:6px;animation:grow .8s var(--ease) both}
@keyframes grow{from{width:0}}
.hrow em{font-style:normal;font-size:11px;color:var(--muted);width:18px}
.hrow.caps span{font-weight:700;color:var(--lime)}
.cal{display:flex;justify-content:space-between;align-items:center;gap:10px;height:100%;background:rgba(91,156,246,.1);border:1px solid rgba(91,156,246,.3);border-radius:14px;padding:12px 14px}
.cal small{color:var(--blue);font-weight:700;font-size:11px}.cal b{display:block;font-size:14px;color:#fff}.cal span{color:var(--muted);font-size:11px}
.agent{position:relative;height:100%;border-radius:14px;padding:11px 13px;background:rgba(245,197,66,.08);border:1px solid rgba(245,197,66,.35);display:flex;flex-direction:column;gap:7px}
.agent b{font-size:12.5px;color:#fff}.agent code{font:11px ui-monospace,SFMono-Regular,Menlo,monospace;background:rgba(255,255,255,.07);padding:6px 8px;border-radius:7px;color:#e9ecef}
.agent .btns{display:flex;gap:6px;margin-top:auto}
.pill{padding:5px 11px;border-radius:999px;font-size:11px;font-weight:700;background:rgba(255,255,255,.09);transition:transform .2s;white-space:nowrap}
.pill.go{background:var(--lime);color:#000}.pill.pressed{transform:scale(.88)}
.okmsg{position:absolute;inset:0;display:grid;place-items:center;font-weight:800;color:var(--lime);font-size:14px;opacity:0;transition:opacity .3s}
.agent.ok .okmsg{opacity:1}.agent.ok>*:not(.okmsg){opacity:.1}
.clip{display:flex;flex-direction:column;gap:6px;height:100%}
.clip .search{height:24px;border-radius:12px;background:rgba(255,255,255,.07);padding:0 10px;display:flex;gap:6px;align-items:center;color:var(--faint);font-size:11px}
.clip .row{display:flex;gap:8px;align-items:center;padding:5px 8px;border-radius:9px;background:rgba(255,255,255,.04);font-size:11px;animation:pop .45s var(--ease) both;animation-delay:calc(var(--i)*70ms)}
.clip .row i{width:18px;height:18px;border-radius:5px;background:var(--c);flex:none}
.tools{display:grid;grid-template-columns:1.3fr 1fr 1fr;gap:8px;height:100%}
.tools div{border-radius:12px;background:rgba(255,255,255,.06);display:flex;align-items:center;justify-content:center;flex-direction:column;gap:4px;font-size:10.5px}
.tools .i{width:15px;height:15px;color:#b9bec6}
.tools .big{grid-row:span 2;font:600 26px ui-rounded,-apple-system,sans-serif;color:#fff}.tools .big small{font-size:10px;color:var(--muted)}
.marquee{border-block:1px solid var(--line);overflow:hidden;padding:20px 0;background:var(--bg2);-webkit-mask:linear-gradient(90deg,transparent,#000 10%,#000 90%,transparent);mask:linear-gradient(90deg,transparent,#000 10%,#000 90%,transparent)}
.marquee .track{display:flex;gap:44px;width:max-content;animation:scroll 42s linear infinite;font-weight:650;color:var(--muted);font-size:16px}
.marquee:hover .track{animation-play-state:paused}
.marquee .track span{display:flex;gap:44px;align-items:center;white-space:nowrap}
.marquee .track span::after{content:"";width:4px;height:4px;border-radius:50%;background:var(--faint)}
@keyframes scroll{to{transform:translateX(-50%)}}
.fnav{position:sticky;top:72px;z-index:40;display:flex;justify-content:center;padding:14px 12px 0;pointer-events:none;height:0;overflow:visible}
.fnav div{pointer-events:auto;display:flex;gap:2px;overflow-x:auto;scrollbar-width:none;padding:5px;border-radius:999px;background:rgba(18,19,23,.82);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);border:1px solid var(--line);max-width:100%;height:max-content}
.fnav div::-webkit-scrollbar{display:none}
.fnav a{padding:6px 12px;border-radius:999px;font-size:13.5px;color:var(--muted);white-space:nowrap;font-weight:620;transition:background .25s,color .25s}
.fnav a:hover{color:var(--text)}.fnav a.on{background:rgba(166,242,92,.13);color:var(--lime)}
#notch{overflow-x:clip}
.story{display:grid;grid-template-columns:1.15fr 1fr;gap:60px;align-items:start}
.sticky{position:sticky;top:18vh}
.sticky .mac{margin:0}
.steps{display:flex;flex-direction:column;gap:min(30vh,300px);padding:min(14vh,140px) 0 min(26vh,260px)}
.step{opacity:.28;transition:opacity .5s,transform .5s var(--ease);transform:translateX(16px)}
.step.active{opacity:1;transform:none}
.step .n{display:flex;gap:8px;align-items:center;font:600 13px ui-monospace,Menlo,monospace;color:var(--muted)}
.step .n .i{width:16px;height:16px;color:var(--lime)}
.step h3{font-size:clamp(24px,2.6vw,32px);letter-spacing:-.02em;margin:6px 0 10px;line-height:1.1}
.step p{color:var(--muted);margin:0;font-size:17px}
.moods{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:70px}
.mood{margin:0;background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:18px 14px 16px;text-align:center;transition:border-color .3s}
.mood:hover{border-color:var(--line2)}
.mood canvas{width:min(150px,70%);aspect-ratio:1;height:auto;display:block;margin:0 auto 8px}
.mood figcaption{font-size:14.5px;color:var(--soft);font-weight:600}
.play{display:grid;grid-template-columns:1fr 1.05fr;gap:40px;align-items:center}
.stage{position:relative;aspect-ratio:1;border-radius:30px;background:radial-gradient(circle at 50% 45%,var(--stage,rgba(166,242,92,.2)),transparent 60%),var(--surface);border:1px solid var(--line);display:grid;place-items:center;overflow:hidden;cursor:pointer}
.stage canvas{width:74%;height:74%}
.stage .tag{position:absolute;bottom:18px;left:0;right:0;text-align:center;font-weight:800;font-size:20px;margin:0}
.stage .tag .rar{font-size:12px;letter-spacing:.12em;color:var(--lime)}
.stage .hint{position:absolute;top:16px;left:0;right:0;text-align:center;font-size:13px;color:var(--faint);margin:0}
.controls{display:flex;flex-direction:column;gap:20px}
.controls h3{font-size:26px;letter-spacing:-.02em;margin:0}.controls>p{margin:0}
.ctl .fh{margin-bottom:8px}
.chips{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.chip{padding:8px 13px;border-radius:999px;background:var(--surface);border:1px solid var(--line);font-weight:600;font-size:14px;transition:all .2s}
.chip:hover{transform:translateY(-2px)}.chip.on{border-color:var(--lime);color:var(--lime);background:rgba(166,242,92,.07)}
.sw{width:32px;height:32px;border-radius:50%;border:2px solid transparent;transition:transform .2s var(--spring)}
.sw:hover{transform:scale(1.15)}.sw.on{border-color:#fff}
.colors{display:flex;gap:14px;align-items:center;flex-wrap:wrap}
.colors label{display:flex;gap:8px;align-items:center;font-size:14px;color:var(--muted)}
input[type=color]{width:32px;height:32px;border:0;border-radius:50%;padding:0;background:none;cursor:pointer}
input[type=color]::-webkit-color-swatch-wrapper{padding:0}input[type=color]::-webkit-color-swatch{border:2px solid rgba(255,255,255,.3);border-radius:50%}
.agents{display:grid;grid-template-columns:1.2fr 1fr;gap:40px;align-items:center}
.term{position:relative;border-radius:18px;background:#0b0c0f;border:1px solid var(--line);box-shadow:0 40px 80px -30px #000;overflow:hidden;font:13.5px/1.7 ui-monospace,SFMono-Regular,Menlo,monospace}
.tbar{height:34px;background:#16171b;display:flex;align-items:center;gap:7px;padding:0 14px}
.tbar i{width:11px;height:11px;border-radius:50%;background:#ff5f57}.tbar i:nth-child(2){background:#febc2e}.tbar i:nth-child(3){background:#28c840}
.tbar span{margin-left:auto;margin-right:auto;color:var(--faint);font-size:12px;transform:translateX(-24px)}
.term pre{margin:0;padding:18px 20px;min-height:270px;white-space:pre-wrap;color:#cfd3d8}
.term .p{color:var(--lime)}.term .d{color:var(--faint)}.term .y{color:var(--gold)}
.caret{display:inline-block;width:8px;height:15px;background:var(--lime);vertical-align:-2px;animation:blink 1s steps(1) infinite}
.agent-pet{display:grid;place-items:center;gap:10px;text-align:center}
.agent-pet canvas{width:220px;height:220px}
.status{font-weight:700;padding:8px 14px;border-radius:999px;background:rgba(255,255,255,.06);border:1px solid var(--line);transition:all .3s;margin:0}
.status.work{color:var(--lime)}.status.need{color:var(--gold);border-color:rgba(245,197,66,.4)}.status.ok{background:var(--lime);color:#000}
.kd{display:grid;grid-template-columns:1.35fr 1fr;gap:28px;align-items:center}
.kd-win{position:relative;border-radius:18px;background:#f5f5f7;color:#1d1f23;box-shadow:0 40px 80px -30px #000;overflow:hidden}
.kd-head{display:flex;gap:7px;align-items:center;padding:12px 14px;background:#e7e8eb}
.kd-head i{width:11px;height:11px;border-radius:50%;background:#ff5f57}.kd-head i:nth-child(2){background:#febc2e}.kd-head i:nth-child(3){background:#28c840}
.kd-head span{margin:0 auto;font-size:13px;font-weight:600;color:#555a62;transform:translateX(-24px)}
.kd-row{padding:9px 20px;border-bottom:1px solid #e1e2e6;font-size:14.5px;color:#1d1f23}.kd-row span{color:#6b7079;margin-right:12px;display:inline-block;min-width:54px}
.kd-text{padding:20px;min-height:150px;font-size:17px;line-height:1.55;transition:background .3s}
.kd-text.working{background:linear-gradient(100deg,transparent 20%,rgba(166,242,92,.35) 50%,transparent 80%);background-size:200% 100%;animation:shimmer 1s linear infinite;color:#8a8f97}
.listening .kd-text::after{content:"";display:inline-block;width:2px;height:1.1em;margin-left:3px;background:#2f7d12;vertical-align:-3px;animation:blink .8s steps(1) infinite}
.kd-foot{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:11px 16px;background:#fbfbfc;border-top:1px solid #e1e2e6;font-size:13px;color:#4d525a}
.kd-hint{font-weight:650;color:#2f7d12}
.kd-vers{display:flex;gap:5px;align-items:center}.kd-vers i{width:7px;height:7px;border-radius:50%;background:#c9ccd2}.kd-vers i.on{background:#2f7d12}.kd-vers span{margin-left:6px}
.kd-top{display:flex;gap:20px;align-items:center;margin-bottom:18px}
.kd-top canvas{width:110px;height:110px}
.keycap{width:126px;height:72px;border-radius:14px;background:linear-gradient(#2c2e34,#1a1b1f);border:1px solid var(--line2);box-shadow:0 6px 0 #0a0b0d,0 10px 24px -8px #000;display:grid;place-items:center;align-content:center;gap:0;transition:transform .12s,box-shadow .12s;font-size:24px}
.keycap small{font-size:11px;color:var(--muted);letter-spacing:.06em}
.keycap.down{transform:translateY(5px);box-shadow:0 1px 0 #0a0b0d,0 0 0 3px rgba(166,242,92,.4),0 0 30px rgba(166,242,92,.3)}
.kd-btns{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.kd-btn{text-align:left;padding:11px 14px;border-radius:14px;background:var(--surface);border:1px solid var(--line);transition:border-color .2s,background .2s,transform .2s var(--spring)}
.kd-btn:hover{transform:translateY(-2px);border-color:var(--line2)}
.kd-btn b{display:block;font-size:12px;color:var(--lime);letter-spacing:.04em;text-transform:uppercase}.kd-btn span{font-size:14.5px;font-weight:600}
.kd-btn.on{border-color:var(--lime);background:rgba(166,242,92,.07)}
.kd-reset{font-size:14px;color:var(--muted);text-decoration:underline;text-underline-offset:3px;justify-self:start;padding:10px 4px}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-top:16px}
.stat{border-radius:22px;padding:24px;background:var(--surface);border:1px solid var(--line)}
.stat b{display:block;font-size:clamp(30px,3.6vw,44px);letter-spacing:-.04em;font-weight:850;background:linear-gradient(var(--text),#9aa0a8);-webkit-background-clip:text;background-clip:text;color:transparent;line-height:1.15}
.stat span{color:var(--muted);font-size:15px}
.chipsline{color:var(--muted);font-size:15px;margin:22px 0 0}
.split{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
.ticks{list-style:none;padding:0;margin:0;display:grid;gap:10px;color:var(--soft)}
.ticks li{display:flex;gap:10px;align-items:center}.ticks .i{color:var(--lime)}
.ticks.cols{grid-template-columns:1fr 1fr;margin-top:28px}
.chatbox{background:#000;border:1px solid var(--line);border-top:0;border-radius:0 0 34px 34px;padding:16px 20px 22px;box-shadow:0 50px 90px -30px #000,0 0 0 1px rgba(255,255,255,.04);display:flex;flex-direction:column;gap:10px;min-height:380px}
.chat-top{display:flex;gap:10px;align-items:center;padding-bottom:6px;border-bottom:1px solid var(--line)}
.chat-top canvas{width:40px;height:40px}.chat-top span{color:var(--faint);font-size:13px}
.msg{opacity:0;transform:translateY(8px);transition:opacity .4s,transform .5s var(--ease);font-size:15px;line-height:1.45}.msg.in{opacity:1;transform:none}
.msg.me{margin-left:auto;background:var(--lime);color:#07120a;border-radius:16px 16px 4px 16px;padding:9px 14px;max-width:85%;font-weight:550}
.msg.gob{background:rgba(255,255,255,.08);border-radius:16px 16px 16px 4px;padding:9px 14px;max-width:85%;width:fit-content}
.msg.brief{border:1px solid rgba(91,156,246,.35);background:rgba(91,156,246,.08);border-radius:16px;padding:12px 14px;color:var(--soft)}
.msg.brief b{display:flex;gap:7px;align-items:center;color:var(--blue);font-size:13px;margin-bottom:4px}
.msg.nudge{font-size:13.5px;color:var(--muted);text-align:center;padding:6px}
.mem-grid{display:grid;grid-template-columns:1.25fr 1fr;gap:16px;align-items:start;margin:10px 0 80px}
.h3{font-size:clamp(24px,2.6vw,32px);letter-spacing:-.02em;margin:0 0 12px}
.mcp{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center}
.mcp-card{background:var(--surface);border:1px solid var(--line);border-radius:26px;padding:26px}
.mcp-card p{color:var(--muted);font-size:15px;margin:18px 0 0}
.switch-row{display:flex;justify-content:space-between;align-items:center;gap:12px;font-weight:650;padding-bottom:18px;border-bottom:1px solid var(--line)}
.switch-row span:first-child{display:flex;gap:10px;align-items:center}
.switch{width:46px;height:28px;border-radius:999px;background:var(--lime);position:relative;flex:none}
.switch i{position:absolute;top:3px;right:3px;width:22px;height:22px;border-radius:50%;background:#fff;box-shadow:0 2px 6px rgba(0,0,0,.3)}
.clients{display:flex;flex-wrap:wrap;gap:8px;margin-top:18px}
.tools-list{display:flex;flex-wrap:wrap;gap:6px;margin-top:16px}.tools-list code{font:12.5px ui-monospace,Menlo,monospace;padding:4px 8px;border-radius:8px;background:rgba(166,242,92,.07);border:1px solid rgba(166,242,92,.18);color:var(--lime)}
.clients span{padding:8px 14px;border-radius:12px;background:var(--raised);border:1px solid var(--line2);font-weight:650;font-size:14.5px;animation:pop .5s var(--spring) both;animation-delay:calc(var(--i)*90ms)}
.cmp-links{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-top:22px}
.cmp-links a{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:14px 16px;border-radius:14px;background:var(--surface);border:1px solid var(--line);font-weight:650;font-size:15px;transition:border-color .2s}
.cmp-links a:hover{border-color:var(--lime)}.cmp-links .i{color:var(--lime)}
@media (max-width:900px){
  .story,.agents,.play,.kd,.split,.mcp,.mem-grid{grid-template-columns:1fr}
  .sticky{position:relative;top:0}
  .steps{gap:36px;padding:30px 0}
  .step{opacity:1;transform:none}
  .stats{grid-template-columns:1fr 1fr}
  .notch.open{width:92%}
  .panel{left:calc(min(120px,22%) + 30px)}
  .cmp-links{grid-template-columns:1fr 1fr}
  .ticks.cols{grid-template-columns:1fr}
  .fnav{top:66px}
}
@media (max-width:560px){
  .hero{padding-top:118px}
  .moods{grid-template-columns:1fr 1fr}
  .mac{border-radius:16px 16px 8px 8px;padding:8px 8px 0}
  .menubar span,.desk-icons{display:none}
  .notch{width:120px;height:20px}.notch .mini{width:16px;height:16px;top:2px}.notch .wing{top:3px}
  .notch.open{height:74%;width:96%}
  .notch.open .mini{left:10px;top:30px;width:22%}
  .panel{left:calc(22% + 20px);right:10px;top:30px;bottom:10px;font-size:10px}
  .tabs{top:6px;left:12px}.tabs i{width:12px;height:9px}
  .music .art{width:40px;height:40px}.tools .big{font-size:18px}
  .agent{padding:8px}.agent code{display:none}.pill{padding:4px 8px}
  .kd-btns{grid-template-columns:1fr}
  .cmp-links{grid-template-columns:1fr}
  .stat{padding:18px}
}
@media (prefers-reduced-motion:reduce){.hero h1 .w,.hero .mac{opacity:1;transform:none;filter:none}.cursor,.flyer{display:none}.marquee .track{animation:none}}
.static .hero h1 .w,.static .hero .mac{opacity:1;transform:none;filter:none}
.static .cursor,.static .flyer{display:none}
.static .sticky{position:relative;top:0}
`
};
