// Every page except home.
import { ic, GH, MCP_LIVE, mcpBadge, cmpTable, CMP_NOTE, FAQ, faqHTML, faqLD, TOOLS, DICTATE_DEMO, TODOS_DEMO, PEOPLE_DEMO, MEMCHAT, DEMO_CSS, subpage, related, appLD } from "./data.mjs";

const tile = (i, h, p) => `<div class="tile2"><h3>${ic(i)}${h}</h3><p>${p}</p></div>`;
const SUB_CSS = `.prose .dk,.prose .people,.prose .todos,.prose .memchat{margin:26px 0}
.prose .tbl{margin:22px 0 6px}
.prose .tile2 h3{margin:0 0 6px}
.feature-group{scroll-margin-top:110px}
.prose .tile2 p{color:var(--muted)}
a.tile2{display:block;text-decoration:none!important;transition:border-color .2s}a.tile2:hover{border-color:var(--lime)}a.tile2 h3{justify-content:space-between;color:var(--text)}
.prose .faq summary{font-size:17px}`;

/* ---------- /features ---------- */
const GROUPS = [
  ["notch", "tray", "Notch basics", "Your MacBook's notch opens into a small panel when you hover it or drop something on it. On Macs without a notch, and on external displays, Gobbl shows a pill at the top of the screen instead.", [
    ["tray", "Drag-and-drop shelf", "Park files in the notch and drag them out anywhere. AirDrop, share or Quick Look them. Shake while dragging and a drop basket appears under your pointer."],
    ["wand", "File tools", "Right-click a shelved file to convert or compress images, compress PDFs and video, remove a photo's background, copy its text or zip it. All on-device."],
    ["clipboard", "Clipboard history", "Press ⇧⌘Space for a searchable history with pins. Copies from password managers are skipped."],
    ["music", "Now Playing with lyrics", "Artwork, controls and synced lyrics for Spotify, Apple Music and YouTube in Chrome, plus an audio output picker."],
    ["speaker", "Volume, brightness and Caps Lock HUDs", "Optional notch-sized replacements for the system pop-ups, plus charging and low-battery notices."],
    ["calendar", "Calendar with Join links", "Your next meeting and a one-click Join button, with a nudge five minutes before."],
    ["timer", "Focus timer and keep-awake", "A focus timer, keep-awake, mic mute, colour picker and copy text from anywhere on screen."]]],
  ["pet", "heart", "The pet", "Gob is a small retro computer with a face on its phosphor screen. Its mood follows what you're doing.", [
    ["eye", "Moods and cursor-following eyes", "Its eyes follow your pointer. It eats files, dances to music, naps when you leave, sweats when the CPU is pegged and nudges you before meetings."],
    ["keyboard", "Types along with you", "An opt-in mode where Gob hops as you type and the letters appear on its screen."],
    ["terminal", "Matrix rain and a thinking face", "While an AI coding agent works, its screen fills with Matrix rain. While the agent plans, it ponders."],
    ["box", "Unboxing", "Pets ship in a box: Classic, Compact or Candy, in one of 8 colours. 1 in 100 are limited editions."],
    ["hat", "Hats, streaks and levels", "Keep a daily streak to level up and earn 11 hats, 4 of them seasonal."],
    ["film", "Skins and clips", "Make and share .gobskin skins. Render a 6-second MP4 and GIF of your pet, or record your real notch."]]],
  ["agents", "terminal", "AI agents in your notch", "Connect Claude Code, Codex and Grok from Settings with one click.", [
    ["terminal", "Agent status", "Gob thinks, codes and celebrates along with Claude Code, Codex and Grok, so you can look away while they work. Codex runs only hooks you've approved, so approve Gobbl's once with /hooks."],
    ["check", "Allow and Deny from the notch", "Claude Code's permission requests appear in the notch. If you don't answer within 30 seconds, Claude asks in the terminal as usual."]]],
  ["key", "keyboard", "Write anywhere with the Gobbl key", "The right Option key works in any text field, in any app.", [
    ["wand", "Tap to write or rewrite", "Tap in an empty field to draft, or with text in it to rewrite. Gobbl uses the nearby text as context."],
    ["layers", "Double-tap for edit mode", "Pick a direction like Shorter, Friendlier, More formal, Fix grammar or Bullet points, and flip between versions."],
    ["mic", "Hold to dictate", "Hold and talk, then let go. The text lands where your cursor is."],
    ["search", "/g for answers", "Type /g and a question in any text field, tap the Gobbl key, and the answer replaces it."]]],
  ["dictation", "mic", "Dictation", "Whisper runs on your Mac. Dictation needs Apple silicon.", [
    ["lock", "Your voice never leaves your Mac", "Audio is transcribed locally with Whisper. There's no word cap and no account."],
    ["bolt", "About 0.5 s per sentence", "Fast enough to feel instant on Apple silicon."],
    ["list", "Three clean-up levels", "Verbatim, Light (removes fillers, fixes punctuation, on your Mac) or Polish with AI."],
    ["globe", "Custom words, language lock, hands-free", "Teach it names and jargon, pin one language for better accuracy, or go hands-free for long thoughts."]]],
  ["chat", "chat", "Chat in the notch", "A small assistant that knows your calendar and your to-dos.", [
    ["bell", "Reminders in plain English", "\"Remind me every weekday at 10 to post standup.\" One-off or repeating."],
    ["sun", "Morning brief and evening wrap", "A short summary of your day ahead, and of what got done."],
    ["calendar", "Pre-meeting briefs", "Ten minutes before a meeting with people Gobbl knows, a short brief on who they are and what you last discussed (with Memory on)."],
    ["heart", "Gentle nudges", "At most three a day, inside your active hours, and never while you're focusing."]]],
  ["memory", "brain", "Memory (opt-in beta)", "Gobbl can remember what was on your screen, so you don't have to.", [
    ["eyeoff", "Reads text, never screenshots", "Text from the front window, through macOS Accessibility, stored on your Mac only."],
    ["lock", "Secrets masked, sensitive places skipped", "Card numbers, keys, passwords and codes are masked. Password fields, private windows and banking sites are skipped."],
    ["check", "Automatic to-dos", "Each with its source and the reason it's a to-do. They tick themselves off when proof appears, with Undo."],
    ["users", "People and projects", "Who-is-who cards for people, projects, organisations and topics, with \"Same person?\" merges."],
    ["search", "Search by meaning, on your Mac", "Semantic search runs on-device with Apple's sentence embeddings. The memory chat answers with cited sources."],
    ["calendar", "Day digests and a timeline", "A short digest of each day and a timeline you can scroll back through, in the Memory window."],
    ["pause", "Pause and forget", "Pause it, forget a recent stretch, forget an app or forget everything. A notch indicator shows when it's on."]]],
  ["mcp", "plug", "MCP connector", "Part of the Memory beta. One switch in Settings, AI Agents, connects your memory to the AI apps you already use.", [
    ["plug", "Nine apps, one switch", "Claude Code, Claude Desktop, Codex (which covers the ChatGPT desktop app too), Cursor, VS Code, Windsurf, Gemini CLI, LM Studio and Zed. Any other MCP app can use the copyable command."],
    ["search", "Memory tools", "search_memory, get_day, list_todos, who_is, get_person, get_project and recent_activity read your memory."],
    ["bell", "Actions through the app", "get_clipboard, add_reminder and mark_todo_done go through the running app."],
    ["log", "Cited and logged", "Answers cite their source, like \"WhatsApp · Samar · Today 7:22 PM\". Each call is logged on your Mac by tool name and time only."]]],
  ["privacy", "shield", "Privacy", "Local first, with receipts.", [
    ["monitor", "Local first", "The notch, the pet, dictation audio and Memory's store stay on your Mac."],
    ["shield", "A provider that keeps nothing", "AI requests go through Xeve's service to a provider that doesn't keep data."],
    ["log", "A log of everything sent", "Every AI request is logged on your Mac."],
    ["github", "Open source", "MIT licensed. No analytics in the app and no account."]]]
];
const features = {
  file: "features.html", url: "/features", priority: "0.9",
  title: "Gobbl features: notch, pet, dictation, AI writing and memory",
  desc: "Every Gobbl feature: notch shelf and clipboard, Now Playing, HUDs, a pet, Claude Code approvals, the Gobbl key, offline dictation, chat and screen memory.",
  crumbs: [["/features", "Features"]], ld: [appLD],
  css: SUB_CSS,
  body: subpage({
    kicker: `${ic("layers")}Features`, h1: "Every Gobbl feature, in one place",
    lede: "Gobbl is a notch app for Mac, a pet, a writing and dictation tool and an opt-in memory, in one free, open-source app. Here's all of it.",
    meta: [["check", "Free and MIT licensed"], ["monitor", "macOS 14+"], ["mic", "Dictation on Apple silicon"]],
    pet: { char: "classic", hue: .13, mood: "happy", rest: "happy" },
    toc: GROUPS.map(([id, , t]) => [id, t.replace(/ \(.*\)/, "")]),
    content: GROUPS.map(([id, , title, intro, items]) => `<section class="feature-group" id="${id}"><h2>${title}${id === "mcp" ? mcpBadge : ""}</h2><p>${intro}</p>${items.length ? `<div class="grid2">${items.map(([i, h, p]) => tile(i, h, p)).join("")}</div>` : ""}${
      id === "dictation" ? `<p><a href="/dictation">More about offline dictation</a></p>` : id === "memory" ? `<p><a href="/memory">How Memory works</a></p>` : id === "privacy" ? `<p><a href="/privacy">Read the privacy page</a></p>` : ""}</section>`).join("\n")
      + related([["/compare/", "Compare Gobbl", "How it lines up with notch, dictation and memory apps."], ["/faq", "FAQ", "Pricing, requirements, privacy and more."]])
  })
};

/* ---------- /dictation ---------- */
const dictation = {
  file: "dictation.html", url: "/dictation", priority: "0.9",
  title: "Free offline dictation for Mac, with Whisper | Gobbl",
  desc: "Free, on-device Whisper dictation for Mac. About 0.5 s per sentence on Apple silicon, no word cap, no account, and your voice never leaves your Mac.",
  crumbs: [["/dictation", "Dictation"]], css: DEMO_CSS + SUB_CSS,
  body: subpage({
    kicker: `${ic("mic")}Dictation`, h1: "Free offline dictation for Mac, powered by Whisper",
    lede: "Hold the right Option key, talk, and let go. Gobbl transcribes with OpenAI's Whisper model on your Mac, so your voice never leaves it. There's no word cap and no account.",
    meta: [["bolt", "About 0.5 s per sentence"], ["lock", "Audio stays on your Mac"], ["cpu", "Needs Apple silicon"]],
    pet: { char: "retro", hue: .55, mood: "curious", rest: "curious", hat: "headphones" },
    toc: [["try", "Try it"], ["how", "How it works"], ["cleanup", "Clean-up levels"], ["models", "Whisper models"], ["tune", "Custom words and language"], ["handsfree", "Hands-free mode"], ["privacy", "Privacy"], ["requirements", "Requirements"], ["vs", "Compared with cloud dictation"]],
    content: `
<div class="tldr"><p><strong>In short:</strong> Gobbl gives any Mac with Apple silicon free, offline dictation into any app. It runs Whisper locally, takes about half a second per sentence, and has no word cap, subscription or account.</p></div>
<h2 id="try">Try it</h2>
<p>This demo shows the flow and the three clean-up levels. The real thing listens to your microphone; this page doesn't.</p>
${DICTATE_DEMO}
<h2 id="how">How it works</h2>
<ol class="steps3"><li><b>Hold the Gobbl key</b>The right Option key, in any text field: Mail, Slack, Notes, a browser, your code editor.</li><li><b>Talk</b>Gobbl starts recording instantly, so nothing is lost while the model wakes up.</li><li><b>Let go</b>Whisper transcribes on your Mac and the text lands where your cursor is.</li></ol>
<p>The first time, pick a Whisper model in Settings and Gobbl downloads it once. After that, dictation works offline.</p>
<h2 id="cleanup">Three clean-up levels</h2>
<div class="grid3">${tile("list", "Verbatim", "Exactly what you said, ums and all.")}${tile("wand", "Light", "Removes filler words and fixes punctuation, on your Mac. The default.")}${tile("layers", "Polish with AI", "Tidies the text into clear writing. Only the text is sent, never the audio.")}</div>
<h2 id="models">Whisper models</h2>
<div class="scroll"><table class="data"><thead><tr><th>Model</th><th>Size</th><th>Best for</th></tr></thead><tbody>
<tr><td>Whisper Small</td><td>About 480 MB</td><td>Recommended: the balance of speed and accuracy</td></tr>
<tr><td>Whisper Turbo</td><td>About 630 MB</td><td>The most accurate, a little slower</td></tr>
<tr><td>Whisper Base</td><td>About 150 MB</td><td>The fastest and smallest</td></tr></tbody></table></div>
<p>You can switch or remove the model any time in Settings, Dictation.</p>
<h2 id="tune">Custom words and language lock</h2>
<p>Add names, products and jargon as custom words, and Whisper spells them your way. Whisper can detect your language automatically, but picking one language gives better results, especially if you mix languages when you speak.</p>
<h2 id="handsfree">Hands-free mode</h2>
<p>For longer thoughts, double-tap and hold the Gobbl key to start hands-free dictation, then tap once to stop. No need to keep a finger down.</p>
<h2 id="privacy">Your voice stays on your Mac</h2>
<p>Audio is recorded and transcribed on your Mac, then thrown away. Nothing is uploaded, which is also why there's no word limit and no sign-up. If you choose Polish with AI, the finished text goes through Xeve's AI service to a provider that doesn't keep data, and the request shows up in Gobbl's local log. See <a href="/privacy">Privacy</a>.</p>
<h2 id="requirements">Requirements</h2>
<ul><li>A Mac with Apple silicon (M1 or later). Dictation isn't available on Intel Macs; the rest of Gobbl is.</li><li>macOS 14 Sonoma or later.</li><li>Microphone permission, and Accessibility permission so the text can be typed into other apps.</li></ul>
<h2 id="vs">Compared with cloud dictation</h2>
<p>Cloud dictation apps can be excellent, and some work on Windows and phones too. The trade-off is that your audio goes to a server, and free tiers usually cap words. Wispr Flow, for example, is cloud-only, its Pro plan costs $15 a month, and its free desktop tier is capped at 2,000 words a week. Gobbl's dictation is Mac-only, and it's free, offline and uncapped.</p>
<p><a href="/compare/wispr-flow">Read the full Gobbl vs Wispr Flow comparison</a>.</p>
<h2 id="faq">Dictation questions</h2>
<div class="faq">${faqHTML(FAQ["Writing and dictation"].slice(1))}</div>
${related([["/compare/wispr-flow", "Gobbl vs Wispr Flow", "A free, on-device alternative, compared fairly."], ["/features#key", "The Gobbl key", "Write, rewrite and ask in any text field."]])}`
  })
};

/* ---------- /memory ---------- */
const memory = {
  file: "memory.html", url: "/memory", priority: "0.9",
  title: "Screen memory for Mac, private and on-device | Gobbl Memory",
  desc: "Gobbl Memory is opt-in AI memory for your Mac: it reads on-screen text (never screenshots), stores it locally, and finds to-dos that tick themselves off.",
  crumbs: [["/memory", "Memory"]], css: DEMO_CSS + SUB_CSS,
  body: subpage({
    kicker: `${ic("brain")}Memory <span class="badge">Beta &middot; opt-in</span>`, h1: "Screen memory for your Mac that finishes your to-dos",
    lede: "Turn on Memory and Gobbl keeps a private, searchable record of the text you've seen, on your Mac. It finds what you said you'd do, and ticks it off when it's done.",
    meta: [["eyeoff", "Text only, never screenshots"], ["monitor", "Stored on your Mac"], ["pause", "Pause or forget any time"]],
    pet: { char: "candy", hue: .78, mood: "think", rest: "think" },
    toc: [["todos", "Automatic to-dos"], ["people", "People and projects"], ["ask", "Search and ask"], ["window", "The Memory window"], ["capture", "How capture works"], ["skipped", "What it never reads"], ["ai", "What goes to AI"], ["controls", "Your controls"], ["mcp", "MCP connector"], ["vs", "Compared"]],
    content: `
<div class="tldr"><p><strong>In short:</strong> Memory is off until you turn it on. It reads text from the window in front of you (not pixels), masks secrets, skips sensitive places, and stores everything in a local database on your Mac. It's a beta.</p></div>
<h2 id="todos">To-dos that tick themselves off</h2>
<p>When you write "I'll send it tomorrow" in Slack, or an email says "please pay by Friday", Gobbl adds a to-do with its source and the reason it thinks it's one. When proof appears later, like a "Payment successful" page or the message where you sent the file, the to-do ticks itself off. Every automatic tick has Undo.</p>
${TODOS_DEMO}
<h2 id="people">People and projects: who is who</h2>
<p>Gobbl builds a card for each person and project it sees, with where they show up and what you talk about. When two names look like the same person, it asks "Same person?" rather than merging on its own. Hover or tap the graph below.</p>
${PEOPLE_DEMO}
<h2 id="ask">Search by meaning, and ask</h2>
<p>Search for what you remember, not the exact words: search by meaning runs on your Mac with Apple's sentence embeddings. Or ask the memory chat, which answers with numbered sources so you can check where each fact came from.</p>
${MEMCHAT}
<h2 id="window">The Memory window</h2>
<p>Everything Memory knows lives in one window: to-dos, a day-by-day timeline with a short digest of each day, people, projects, organisations and topics, and search. Ten minutes before a meeting with people Gobbl knows, you get a brief on who they are and what you last talked about.</p>
<h2 id="capture">How capture works</h2>
<ul><li>Gobbl reads the text of the front window through macOS Accessibility, the same interface screen readers use. It never takes screenshots or records video.</li><li>It captures when you switch apps or the window changes, and stops while your screen is locked or you're away.</li><li>Text is deduplicated and stored in a SQLite database in your Mac's Application Support folder. It never syncs anywhere.</li></ul>
<h2 id="skipped">What it never reads, and what it masks</h2>
<div class="grid2">${tile("eyeoff", "Skipped", "Password fields, secure input, private and incognito browser windows, banking, brokerage, crypto and health sites, your locked screen, and Gobbl itself.")}${tile("lock", "Masked before saving", "Card numbers, API keys and tokens, passwords, one-time codes, CVVs and IBANs are replaced with a placeholder before anything is stored.")}</div>
<h2 id="ai">What goes to the AI service</h2>
<p>Finding to-dos and writing digests needs a language model. For that, Gobbl sends short, already-masked snippets through Xeve's AI service to a provider that doesn't keep data. Every request is written to a log on your Mac, so you can see exactly what was sent. The memory itself stays on your Mac. See <a href="/privacy">Privacy</a>.</p>
<h2 id="controls">Your controls</h2>
<ul><li><strong>Opt-in:</strong> Memory is off until you turn it on.</li><li><strong>Pause</strong> for a while or until you resume.</li><li><strong>Forget</strong> the last stretch of time, one app, or everything.</li><li><strong>Retention:</strong> old memories are removed automatically after the period you choose.</li><li><strong>Indicator:</strong> a small mark in the notch shows whenever Memory is on.</li></ul>
<h2 id="mcp">Use your memory in other AI apps${mcpBadge}</h2>
<p>Turn on "Connect AI apps automatically" in Settings, AI Agents, and Gobbl registers its MCP helper with Claude Code, Claude Desktop, Codex (which also covers the ChatGPT desktop app), Cursor, VS Code, Windsurf, Gemini CLI, LM Studio and Zed. Any other app that speaks MCP can use the copyable command.</p>
<ul><li><strong>Reading your memory:</strong> <code>search_memory</code>, <code>get_day</code>, <code>list_todos</code>, <code>who_is</code>, <code>get_person</code>, <code>get_project</code> and <code>recent_activity</code>.</li><li><strong>Through the running app:</strong> <code>get_clipboard</code>, <code>add_reminder</code> and <code>mark_todo_done</code>.</li><li><strong>Sources:</strong> answers cite where each fact came from, like "WhatsApp · Samar · Today 7:22 PM".</li><li><strong>Logged:</strong> each call is logged on your Mac by tool name and time only.</li></ul>
<p>Ask Claude Code "what did Priya say about the launch?" and it can look it up. Keep in mind that what an AI app reads from your memory is then handled under that app's own privacy terms.</p>
<h2 id="vs">Compared with other screen memory apps</h2>
${cmpTable(["gobbl", "goldfish", "screenpipe"], "Gobbl compared with Goldfish and Screenpipe", 640)}
${CMP_NOTE}
<p>Rewind, once the best-known Mac screen memory app, stopped working in December 2025. If you're looking for a Rewind alternative that stays on your Mac, Gobbl is one option; <a href="/compare/goldfish">see how it compares with Goldfish</a>.</p>
${related([["/compare/goldfish", "Gobbl vs Goldfish", "Two ways to give your Mac a memory."], ["/privacy", "Privacy", "Exactly what stays local and what doesn't."]])}`
  })
};

/* ---------- /privacy ---------- */
const privacy = {
  file: "privacy.html", url: "/privacy", priority: "0.7",
  title: "Privacy: what Gobbl keeps on your Mac, and what it sends",
  desc: "Gobbl's privacy in plain English: what stays on your Mac, what the AI features send, how the AI provider handles it, and how to check every request yourself.",
  crumbs: [["/privacy", "Privacy"]], css: SUB_CSS,
  body: subpage({
    kicker: `${ic("shield")}Privacy`, h1: "What stays on your Mac, and what doesn't",
    lede: "Gobbl is local first. When a feature needs an AI model, it sends as little as it can, through a provider that keeps nothing, and it logs every request so you can check.",
    meta: [["github", "Open source, MIT"], ["user", "No account"], ["log", "Local log of every AI request"]],
    pet: { char: "retro", hue: .3, mood: "idle", hat: "halo" }, cta: false,
    toc: [["local", "Stays on your Mac"], ["sent", "What AI features send"], ["provider", "The AI provider"], ["log", "The request log"], ["verify", "Verification"], ["website", "This website"], ["contact", "Questions"]],
    content: `
<div class="tldr"><p><strong>In short:</strong> the notch, the pet, your files, clipboard, dictation audio and everything Memory stores stay on your Mac. AI features send only the text they need, through Xeve's service, to a model provider that doesn't keep it. The app has no analytics and no account.</p></div>
<h2 id="local">What stays on your Mac</h2>
<div class="scroll"><table class="data"><thead><tr><th>Feature</th><th>Where it runs</th><th>Leaves your Mac?</th></tr></thead><tbody>
<tr><td>Shelf and file tools</td><td>On your Mac</td><td>No</td></tr>
<tr><td>Clipboard history</td><td>On your Mac (password-manager copies are skipped)</td><td>No</td></tr>
<tr><td>Now Playing</td><td>On your Mac. Lyrics are looked up from lrclib.net by song title, if you turn lyrics on</td><td>Song title only, for lyrics</td></tr>
<tr><td>Pet, skins, streaks</td><td>On your Mac</td><td>No</td></tr>
<tr><td>Dictation</td><td>Whisper on your Mac</td><td>Audio: never. Text: only with Polish with AI</td></tr>
<tr><td>Memory</td><td>Stored in a local database</td><td>Masked snippets, to find to-dos and write digests</td></tr>
<tr><td>MCP connector (if on)</td><td>Local helper on your Mac</td><td>Only to the AI apps you connect; calls logged by tool name and time</td></tr>
<tr><td>Gobbl key, chat, briefs</td><td>AI service</td><td>The text you ask about, with nearby context</td></tr>
</tbody></table></div>
<h2 id="sent">What the AI features send</h2>
<ul><li><strong>Gobbl key:</strong> the text you ask it to write or rewrite, plus nearby text for context.</li><li><strong>Chat, reminders, briefs:</strong> your messages and a short summary of your day (calendar and to-dos) so the answer makes sense.</li><li><strong>Polish with AI:</strong> the transcribed text, never the audio.</li><li><strong>Memory (if on):</strong> short snippets, with secrets already masked, to find to-dos and build digests.</li></ul>
<p>The AI features are free during the beta. They'll become a paid plan later; this page will be updated if anything about how data is handled changes.</p>
<h2 id="provider">The AI provider</h2>
<p>Requests go to Xeve's AI service, which forwards them to a model through OpenRouter with data collection turned off, so the provider doesn't keep your text or train on it. Xeve's service keeps only what it needs to enforce fair-use limits.</p>
<h2 id="log">A log of everything sent</h2>
<p>Every AI request is written to a log on your Mac, which you can open from Settings. If you want to know exactly what left your Mac and when, it's all there.</p>
<h2 id="verify">One-time verification</h2>
<p>To keep the free AI service from being abused, the first AI request asks for a one-time Cloudflare Turnstile check. It doesn't create an account.</p>
<p>If you choose to pay what you want, checkout is handled by Dodo Payments, which acts as the merchant of record and processes your name, email and payment details under its own privacy policy. Xeve receives a record of the payment, not your card details. Paying is optional and unlocks nothing: the app is the same either way.</p>
<h2 id="website">This website</h2>
<p>The Gobbl app has no analytics. This website, gobbl.xeve.io, uses Google Analytics to count visits and clicks on the download and GitHub buttons.</p>
<h2 id="contact">Questions</h2>
<p>Gobbl is open source, so you can read exactly how it handles data <a href="${GH}">on GitHub</a>. Questions or concerns: <a href="${GH}/issues">open an issue</a> or reach Xeve at <a href="https://xeve.io">xeve.io</a>.</p>
${related([["/memory", "Memory", "What screen memory reads, skips and masks."], ["/dictation", "Dictation", "Why your voice never leaves your Mac."]])}`
  })
};

/* ---------- /faq ---------- */
const allFaq = Object.values(FAQ).flat();
const faq = {
  file: "faq.html", url: "/faq", priority: "0.8",
  title: "Gobbl FAQ: price, Mac requirements, dictation, memory, privacy",
  desc: "Answers about Gobbl: is it free, which Macs it runs on, how on-device dictation and Memory work, what the AI features send, and how the Claude Code link works.",
  crumbs: [["/faq", "FAQ"]], ld: [faqLD(allFaq)], css: SUB_CSS,
  body: subpage({
    kicker: `${ic("chat")}FAQ`, h1: "Gobbl questions, answered",
    lede: "Everything people ask about Gobbl, the free notch app for Mac: price, requirements, the pet, dictation, Memory, privacy and AI agents.",
    pet: { char: "candy", hue: .13, mood: "curious", rest: "curious" },
    toc: Object.keys(FAQ).map(k => [k.toLowerCase().replace(/\W+/g, "-"), k]),
    content: Object.entries(FAQ).map(([k, list]) => `<h2 id="${k.toLowerCase().replace(/\W+/g, "-")}">${k}</h2><div class="faq">${faqHTML(list)}</div>`).join("\n")
  })
};

/* ---------- compare ---------- */
const hub = {
  file: "compare/index.html", url: "/compare/", priority: "0.8",
  title: "Gobbl vs notch, dictation and memory apps for Mac",
  desc: "Gobbl compared honestly with Droppy, NotchNook, Boring Notch, Alcove, Wispr Flow, Superwhisper, Goldfish and Screenpipe: price, open source and privacy.",
  crumbs: [["/compare/", "Compare"]], css: SUB_CSS + ".prose{max-width:none}.page{grid-template-columns:minmax(0,1fr)}.page .aside{display:none}",
  body: subpage({
    kicker: `${ic("list")}Compare`, h1: "Gobbl compared with other Mac notch, dictation and memory apps",
    lede: "Gobbl overlaps with three kinds of Mac app. Here's how it lines up, as fairly as we can put it, with sources and dates.",
    pet: { char: "retro", hue: .3, mood: "think", rest: "think" },
    content: `
<h2 id="table">The full comparison</h2>
${cmpTable(["gobbl", "droppy", "notchnook", "boring", "alcove", "wispr", "superwhisper", "goldfish", "screenpipe"], "Gobbl compared with notch, dictation and memory apps for Mac")}
${CMP_NOTE}
<h2 id="pages">Head-to-head comparisons</h2>
<div class="grid2">
<a class="tile2" href="/compare/wispr-flow"><h3>Gobbl vs Wispr Flow${ic("arrow")}</h3><p>Free on-device dictation versus a polished cloud service.</p></a>
<a class="tile2" href="/compare/droppy"><h3>Gobbl vs Droppy${ic("arrow")}</h3><p>Two notch apps with shelves, clipboards and agent status.</p></a>
<a class="tile2" href="/compare/notchnook"><h3>Gobbl vs NotchNook${ic("arrow")}</h3><p>A free, open-source NotchNook alternative with a pet.</p></a>
<a class="tile2" href="/compare/goldfish"><h3>Gobbl vs Goldfish${ic("arrow")}</h3><p>Two approaches to giving your Mac a memory.</p></a>
</div>
<h2 id="pick">Which should you pick?</h2>
<ul><li><strong>Just want a notch shelf and music?</strong> Boring Notch is free and open source too, and Alcove is a polished paid option. Gobbl adds the pet, the Gobbl key, dictation and Memory.</li><li><strong>Dictation on several devices?</strong> Wispr Flow and Superwhisper cover Windows and phones; Gobbl is Mac-only.</li><li><strong>Screen memory on Windows or Linux?</strong> Screenpipe runs on all three; Goldfish runs on Mac and Windows.</li><li><strong>All of it in one free Mac app?</strong> That's what Gobbl is for.</li></ul>`
  })
};

function versus({ slug, key, title, desc, h1, lede, pet, tldr, theirs, ours, pick, extra = "", rel }) {
  const t = TOOLS[key];
  return {
    file: `compare/${slug}.html`, url: `/compare/${slug}`, priority: "0.8", title, desc, ogType: "article",
    crumbs: [["/compare/", "Compare"], [`/compare/${slug}`, `Gobbl vs ${t.name}`]], css: SUB_CSS,
    body: subpage({
      kicker: `${ic("list")}Gobbl vs ${t.name}`, h1, lede, pet,
      toc: [["short", "The short version"], ["table", "Side by side"], ["theirs", `Where ${t.name} is stronger`], ["ours", "Where Gobbl is stronger"], ["pick", "Which to pick"]],
      content: `
<h2 id="short">The short version</h2>
<div class="tldr">${tldr}</div>
<h2 id="table">Gobbl and ${t.name}, side by side</h2>
${cmpTable(["gobbl", key], `Gobbl compared with ${t.name}`, 560)}
${CMP_NOTE.replace(" Rewind isn't in the table because it stopped recording on 19 December 2025, after Meta acquired Limitless.", "")}
<h2 id="theirs">Where ${t.name} is stronger</h2>
<ul>${theirs.map(x => `<li>${x}</li>`).join("")}</ul>
<h2 id="ours">Where Gobbl is stronger</h2>
<ul>${ours.map(x => `<li>${x}</li>`).join("")}</ul>
${extra}
<h2 id="pick">Which to pick</h2>
${pick}
<p>${t.name}'s website: <a href="${t.url}" rel="noopener">${t.url.replace("https://", "")}</a>.</p>
${related(rel)}`
    })
  };
}

const vsWispr = versus({
  slug: "wispr-flow", key: "wispr",
  title: "Gobbl vs Wispr Flow: a free, on-device Wispr Flow alternative",
  desc: "Looking for a free Wispr Flow alternative for Mac? Gobbl dictates on-device with Whisper, with no word cap or account. A fair, side-by-side comparison.",
  h1: "Gobbl vs Wispr Flow: a free, on-device alternative for Mac",
  lede: "Wispr Flow is a polished cloud dictation service. Gobbl's dictation runs Whisper on your Mac, free and uncapped. Here's how they differ, fairly.",
  pet: { char: "retro", hue: .55, mood: "curious", rest: "curious", hat: "headphones" },
  tldr: `<p>Pick <strong>Gobbl</strong> if you want free dictation on a Mac with Apple silicon, with no word cap, no account, and audio that never leaves your Mac.</p><p>Pick <strong>Wispr Flow</strong> if you need dictation on Windows, iPhone or Android as well, or want its team and cloud features, and are fine with audio going to the cloud.</p>`,
  theirs: ["Runs on Mac, Windows, iOS and Android; Gobbl is Mac-only.", "A mature, polished product focused on dictation, with team plans and SOC 2 and ISO 27001 compliance.", "Cloud models can handle context and formatting in ways that are hard on-device.", "Works on Intel Macs; Gobbl's dictation needs Apple silicon."],
  ours: ["Free, with no word cap. Wispr Flow's free desktop tier is capped at 2,000 words a week, and Pro is $15 a month.", "On-device: your voice is transcribed on your Mac with Whisper and never uploaded.", "No account needed.", "About 0.5 s per sentence on Apple silicon, and it works offline once the model is downloaded.", "Custom words, language lock, hands-free mode and three clean-up levels, including Polish with AI (text only) when you want it.", "Open source under MIT, and dictation is one part of a bigger app: the notch, the pet, the Gobbl key for rewriting, chat and Memory."],
  pick: `<p>If you dictate mostly on a Mac and care about privacy or cost, Gobbl is a strong free Wispr Flow alternative: offline Whisper dictation with no limits. If you dictate across several devices, Wispr Flow's cross-platform sync is worth paying for.</p><p>Learn more about <a href="/dictation">Gobbl's offline dictation</a>.</p>`,
  rel: [["/dictation", "Offline dictation", "How Gobbl's Whisper dictation works."], ["/compare/", "All comparisons", "Superwhisper, Droppy, Goldfish and more."]]
});

const vsDroppy = versus({
  slug: "droppy", key: "droppy",
  title: "Gobbl vs Droppy: a free, open-source Droppy alternative",
  desc: "Gobbl vs Droppy, the notch apps for Mac: shelf, clipboard, dictation, Claude Code status and approvals, memory, a pet, price and licence, compared fairly.",
  h1: "Gobbl vs Droppy: two notch apps for Mac, compared",
  lede: "Droppy and Gobbl both turn the MacBook notch into a shelf, clipboard and control centre. Here's where each one shines.",
  pet: { char: "retro", hue: .3, mood: "eating", rest: "eating" },
  tldr: `<p>Pick <strong>Gobbl</strong> if you want a free, MIT-licensed notch app with a pet, Allow/Deny for Claude Code, the Gobbl key for writing anywhere, and opt-in screen memory.</p><p>Pick <strong>Droppy</strong> if you want a mature, focused notch utility with an iPhone companion and a wider set of extensions, and don't mind a small one-time price.</p>`,
  theirs: ["An iPhone companion app, and end-to-end encrypted sync.", "A larger extension catalogue, including agent status for more coding tools (Claude Code, Codex, Cursor and others).", "On-device dictation too.", "A longer track record as a dedicated notch utility."],
  ours: ["Free, and open source under the MIT license. Droppy costs about $10 once and is source-available under GPL-3.0 with the Commons Clause.", "Answer Claude Code's permission requests from the notch with Allow and Deny; Droppy's agent view is status only.", "The Gobbl key: write, rewrite, edit in versions and ask /g questions in any text field.", "Opt-in screen memory with to-dos that tick themselves off, people and project cards, and a memory chat.", "Chat in the notch with reminders, a morning brief and an evening wrap.", "Gob, a pet with moods, hats, streaks and shareable skins. No other notch app has a character."],
  pick: `<p>Both are good notch apps. If you want a dependable shelf and clipboard with an iPhone companion, Droppy is a fine choice. If you want an open-source Droppy alternative that also writes, remembers and approves your agent's requests, try Gobbl. It's free, so it costs nothing to compare.</p>`,
  rel: [["/compare/notchnook", "Gobbl vs NotchNook", "Another popular notch app, compared."], ["/features#notch", "Notch features", "Shelf, clipboard, music, HUDs and more."]]
});

const vsNook = versus({
  slug: "notchnook", key: "notchnook",
  title: "Gobbl vs NotchNook: a free NotchNook alternative with a pet",
  desc: "A free, open-source NotchNook alternative for MacBook: Gobbl adds dictation, AI writing, Claude Code approvals, opt-in memory and a pet. A fair comparison.",
  h1: "Gobbl vs NotchNook: a free, open-source alternative",
  lede: "NotchNook helped make notch apps popular. Gobbl covers the notch basics too, and adds dictation, AI writing, Memory and a pet, for free.",
  pet: { char: "candy", hue: .93, mood: "dance", rest: "dance" },
  tldr: `<p>Pick <strong>Gobbl</strong> if you want a free, open-source MacBook notch app that also dictates, writes, remembers and watches your AI agents.</p><p>Pick <strong>NotchNook</strong> if you prefer a long-established paid app focused on the notch itself.</p>`,
  theirs: ["One of the best-known notch apps, with a polished, focused design.", "A longer history and a large user base.", "Widgets like the file tray, Now Playing and calendar, refined over many releases."],
  ours: ["Free and open source under MIT. NotchNook is paid and closed source (sources disagree on the current price, so check its site).", "On-device Whisper dictation with no word cap.", "The Gobbl key for writing and rewriting in any app.", "Claude Code, Codex and Grok status, and Allow/Deny for Claude Code from the notch.", "Opt-in screen memory with automatic to-dos.", "A pet that reacts to what you do."],
  pick: `<p>If you only want notch widgets and already own NotchNook, it does that job well. If you're choosing today, Gobbl is a free NotchNook alternative that covers the basics and adds a lot more.</p>`,
  rel: [["/compare/droppy", "Gobbl vs Droppy", "Another notch app, compared."], ["/features", "All features", "Everything Gobbl does."]]
});

const vsGoldfish = versus({
  slug: "goldfish", key: "goldfish",
  title: "Gobbl vs Goldfish: AI screen memory for Mac, compared",
  desc: "Gobbl vs Goldfish, two AI memory apps for Mac: how they capture, where data lives, to-dos, MCP, the notch and price. A fair, sourced comparison.",
  h1: "Gobbl vs Goldfish: two ways to give your Mac a memory",
  lede: "Goldfish and Gobbl both remember what's on your screen and keep it local. They take different paths from there.",
  pet: { char: "candy", hue: .55, mood: "think", rest: "think" },
  tldr: `<p>Pick <strong>Gobbl</strong> if you want screen memory that turns into to-dos that tick themselves off, plus an MCP connector for nine AI apps, a whole notch app, dictation and AI writing, open source.</p><p>Pick <strong>Goldfish</strong> if you want a dedicated memory app with an auto-generated wiki of your work, and a Windows version.</p>`,
  theirs: ["Runs on Mac and Windows.", "Builds an auto-generated wiki of your work from what it sees.", "It connects to Claude Desktop over MCP too, so the two are even there.", "A dedicated memory app, with the whole product focused on it."],
  ours: ["Automatic to-dos, each with its source and reason, that tick themselves off when proof appears, with Undo.", "People and project cards with \"Same person?\" merges, and a memory chat with cited sources.", "Reads accessibility text instead of screenshots, and skips password fields, private windows and banking sites by default.", "Memory is one part of a full notch app: shelf, clipboard, music, HUDs, calendar, a pet, on-device dictation and the Gobbl key.", "Open source under MIT, with a local log of every AI request."],
  extra: `<h2 id="rewind">What about Rewind?</h2><p>Rewind stopped recording on 19 December 2025, after Meta acquired Limitless, so it's no longer an option. Both Gobbl and Goldfish are Rewind alternatives that keep memory on your Mac.</p>`,
  pick: `<p>Both keep your memory local and use a zero-retention AI provider. Goldfish is a focused memory tool that also runs on Windows. Gobbl is for people who want memory to do something, like closing loops on to-dos, inside an app they already use all day. See <a href="/memory">how Gobbl Memory works</a>.</p>`,
  rel: [["/memory", "Gobbl Memory", "What it reads, skips and masks."], ["/privacy", "Privacy", "What stays local and what's sent."]]
});

const notFound = {
  file: "404.html", url: "/404", noindex: true,
  title: "Page not found | Gobbl", desc: "This page doesn't exist. Head back to Gobbl, the free notch app for Mac.",
  body: `<section class="phero" style="padding-top:150px;text-align:center"><div class="wrap"><canvas width="360" height="360" style="width:180px;height:180px" data-gob='{"char":"retro","mood":"think","rest":"think"}' role="img" aria-label="Gob, thinking"></canvas><h1>Gob ate this page.</h1><p class="lede" style="margin:0 auto 28px">It isn't here any more, or it never was.</p><div class="cta" style="justify-content:center"><a class="btn primary" href="/">Go home</a><a class="btn ghost" href="/features">See features</a></div></div></section>`
};

export const subpages = [features, dictation, memory, privacy, faq, hub, vsWispr, vsDroppy, vsNook, vsGoldfish, notFound];
