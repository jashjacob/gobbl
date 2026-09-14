// Shared data and snippets: comparison facts, FAQ, JSON-LD, demo markup and CSS.
export const ORIGIN = "https://gobbl.xeve.io";
// Flip to true once gobbl-mcp ships; every MCP mention on the site follows it.
export const MCP_LIVE = true;
export const mcpBadge = MCP_LIVE ? ' <span class="badge lime">Available (Memory beta)</span>' : ' <span class="badge">Coming soon, with Memory beta</span>';
export const ic = n => `<svg class="i" aria-hidden="true"><use href="#i-${n}"/></svg>`;
export const GH = "https://github.com/xeveio/gobbl";

/* ---------- comparison (checked 14 September 2026) ---------- */
export const TOOLS = {
  gobbl: { name: "Gobbl", kind: "Notch, dictation, memory" },
  droppy: { name: "Droppy", kind: "Notch app", url: "https://getdroppy.app" },
  notchnook: { name: "NotchNook", kind: "Notch app", url: "https://lo.cafe/notchnook" },
  boring: { name: "Boring Notch", kind: "Notch app", url: "https://github.com/TheBoredTeam/boring.notch" },
  alcove: { name: "Alcove", kind: "Notch app", url: "https://tryalcove.com" },
  wispr: { name: "Wispr Flow", kind: "Dictation", url: "https://wisprflow.ai" },
  superwhisper: { name: "Superwhisper", kind: "Dictation", url: "https://superwhisper.com" },
  goldfish: { name: "Goldfish", kind: "Memory", url: "https://goldfish.sh" },
  screenpipe: { name: "Screenpipe", kind: "Memory", url: "https://screenpipe.com" }
};
export const ROWS = [["price", "Price"], ["oss", "Open source"], ["platforms", "Platforms"], ["dictation", "On-device dictation"], ["cap", "Free-tier word cap"], ["memory", "Screen memory and to-dos"], ["mcp", "MCP connector"], ["agents", "AI coding agents in the notch"], ["pet", "Pet"], ["privacy", "Privacy"]];
// y = yes, p = partial or with caveats, n = no, u = not listed / unsure, - = not applicable
export const CMP = {
  gobbl: { price: "y|Free. AI features free during the beta", oss: "y|Yes, MIT", platforms: "-|macOS 14+", dictation: "y|Yes, Whisper on your Mac (Apple silicon)", cap: "y|None", memory: "y|Yes, opt-in beta, with auto-ticking to-dos", mcp: MCP_LIVE ? "y|Yes, one switch for 9 AI apps (Memory beta)" : "p|Coming soon", agents: "y|Claude Code and Codex status, Allow/Deny for Claude Code", pet: "y|Yes, Gob", privacy: "y|Local first; AI via a provider that keeps no data; log of every request" },
  droppy: { price: "p|About $10 one-time", oss: "p|Source-available (GPL-3.0 with Commons Clause)", platforms: "-|macOS 14+, iPhone companion", dictation: "y|Yes, on-device", cap: "-|Paid app", memory: "u|Not listed", mcp: "p|Developer kit only", agents: "p|Status only (Claude Code, Codex, more)", pet: "n|No", privacy: "y|Local first" },
  notchnook: { price: "p|Paid; sources vary", oss: "n|No", platforms: "-|macOS", dictation: "u|Not listed", cap: "-|Paid app", memory: "u|Not listed", mcp: "u|Not listed", agents: "u|Not listed", pet: "n|No", privacy: "u|Varies" },
  boring: { price: "y|Free", oss: "y|Yes, GPL-3.0", platforms: "-|macOS 14+", dictation: "n|No", cap: "-|No dictation", memory: "n|No", mcp: "n|No", agents: "n|No", pet: "n|No", privacy: "y|Local app" },
  alcove: { price: "p|$14.99 one-time", oss: "n|No", platforms: "-|macOS 15+", dictation: "u|Not listed", cap: "-|Paid app", memory: "u|Not listed", mcp: "u|Not listed", agents: "u|Not listed", pet: "n|No", privacy: "u|Varies" },
  wispr: { price: "p|Free tier; Pro $15/month", oss: "n|No", platforms: "-|Mac, Windows, iOS, Android", dictation: "n|Cloud only", cap: "n|2,000 words a week on desktop", memory: "n|No", mcp: "y|Yes, for its notes", agents: "n|No notch", pet: "n|No", privacy: "p|Cloud; optional zero-retention mode" },
  superwhisper: { price: "p|Free tier; Pro $8.49/month", oss: "n|No", platforms: "-|macOS, Windows, iOS", dictation: "y|Yes, local models (cloud optional)", cap: "p|Unlimited on small local models", memory: "u|Not listed", mcp: "u|Not listed", agents: "n|No notch", pet: "n|No", privacy: "y|Works offline" },
  goldfish: { price: "y|Free during beta", oss: "u|Varies", platforms: "-|macOS (Apple silicon), Windows", dictation: "u|Not listed", cap: "-|No dictation", memory: "p|Screen memory; to-dos not listed", mcp: "y|Yes, Claude Desktop", agents: "u|Not listed", pet: "n|Fish theme, no pet", privacy: "y|Local storage; AI via a zero-retention provider" },
  screenpipe: { price: "p|Free for 1 device; paid from $21/month", oss: "p|Source-available", platforms: "-|macOS, Windows, Linux", dictation: "p|Transcribes audio (not dictation)", cap: "-|No dictation", memory: "p|Screen memory; to-dos not listed", mcp: "y|Yes", agents: "n|No notch", pet: "n|No", privacy: "y|Local by default" }
};
const cell = s => { const [k, t] = s.split("|"); return k === "-" ? `<span class="v x">${t}</span>` : `<span class="v ${k}">${t}</span>`; };
export function cmpTable(keys, caption, minw) {
  const head = keys.map(k => `<th scope="col" class="${k === "gobbl" ? "us" : ""}"><small>${TOOLS[k].kind}</small>${TOOLS[k].name}</th>`).join("");
  const body = ROWS.map(([r, label]) => `<tr><th scope="row">${label}</th>${keys.map(k => `<td class="${k === "gobbl" ? "us" : ""}">${cell(CMP[k][r])}</td>`).join("")}</tr>`).join("");
  return `<div class="tbl" tabindex="0" role="region" aria-label="${caption}"><table class="cmp" style="--minw:${minw || keys.length * 150 + 150}px"><caption>${caption}</caption><thead><tr><th scope="col">Feature</th>${head}</tr></thead><tbody>${body}</tbody></table></div>
<div class="legend"><span class="v y">Yes</span><span class="v p">Partly, or with a catch</span><span class="v n">No</span><span class="v u">Not listed on their site</span></div>`;
}
export const CMP_NOTE = `<p class="note">Checked against each product's own website and public sources on 14 September 2026. Prices are in US dollars where the maker lists them; NotchNook's price differs between sources, so we don't quote one. Rewind isn't in the table because it stopped recording on 19 December 2025, after Meta acquired Limitless. Products change quickly: if something here is out of date, <a href="${GH}/issues">open an issue</a> and we'll fix it.</p>`;

/* ---------- FAQ ---------- */
export const FAQ = {
  General: [
    ["Is Gobbl free?", `Yes. Gobbl is free and open source under the MIT license, made by <a href="https://xeve.io">Xeve</a>. The AI features (writing with the Gobbl key, chat, briefs, Polish with AI, Memory's to-dos) are free during the beta and will become a paid plan later. The notch, the pet, the shelf, the clipboard and on-device dictation don't use the AI service at all.`],
    ["Which Macs does Gobbl work on?", `Any Mac running macOS 14 Sonoma or later. Macs without a notch, and external displays, get a small pill at the top of the screen instead. Dictation needs a Mac with Apple silicon. There is no Windows or Linux version.`],
    ["When can I download it?", `Now. <a href="/download">Download Gobbl</a> for macOS 14 or later: it's signed and notarized by Apple, and it updates itself. Every build is also on <a href="${GH}/releases">GitHub releases</a>, and you can build it from source.`],
    ["Do I need an account?", `No. There's no sign-up. To stop abuse of the free AI service, the app does a one-time Cloudflare Turnstile check the first time you use an AI feature.`],
    ["Does it drain my battery?", `No. At rest Gobbl sits around 0% CPU: Gob only redraws to blink, and nothing polls in the background except a cheap clipboard check.`],
    ["Is Gobbl open source?", `Yes, all of it, under the MIT license on <a href="${GH}">GitHub</a>. Gobbl doesn't reuse code from GPL notch apps; third-party code it does use is listed in the repo.`]
  ],
  "Notch and pet": [
    ["What can the notch do?", `Hold files on a drag-and-drop shelf (with convert, compress, background removal, text copy and zip), keep your clipboard history on ⇧⌘Space, show Now Playing with lyrics, replace the volume, brightness and Caps Lock pop-ups, show your next meeting with a Join button, and run a focus timer, keep-awake and other quick tools. See <a href="/features">all features</a>.`],
    ["What is Gob?", `Gob is the pet: a small retro computer with a face on its screen, in three models (Classic, Compact and Candy). It watches your cursor, eats the files you drop, dances to music, types along with you, fills its screen with Matrix rain while your AI agent codes, and levels up with streaks and hats. New pets arrive in a box.`],
    ["Can I make my own skin?", `Yes. Skins are small .gobskin files you can make, share and import. You can also record a 6-second clip of your pet as MP4 and GIF.`]
  ],
  "Writing and dictation": [
    ["What is the Gobbl key?", `The right Option key. Tap it in any text field to write or rewrite, double-tap for edit mode with versions like "shorter" or "friendlier", hold it to dictate, and type /g with a question, then tap it, to get an answer in place.`],
    ["Does my voice leave my Mac?", `No. Dictation runs OpenAI's Whisper model on your Mac, so audio never leaves it. Only if you choose the Polish with AI clean-up level is the transcribed text (never the audio) sent for polishing. More on the <a href="/dictation">dictation page</a>.`],
    ["Is there a word limit on dictation?", `No. There's no word cap and no account, because transcription happens on your Mac.`],
    ["Is Gobbl a free Wispr Flow alternative?", `For dictation on a Mac, yes: it's free, has no word cap and runs on-device. Wispr Flow is cloud-based, works on more platforms and costs $15 a month for Pro. See <a href="/compare/wispr-flow">Gobbl vs Wispr Flow</a>.`]
  ],
  "Memory and privacy": [
    ["What does Memory read?", `Memory is an opt-in beta. When it's on, it reads the text of the window in front of you through macOS Accessibility. It never takes screenshots. It stores that text on your Mac only, masks secrets, and skips password fields, private browser windows and banking sites. See <a href="/memory">Memory</a>.`],
    ["What gets sent to the AI service?", `Only what an AI feature needs: the text you ask it to write or rewrite with some nearby context, your chat messages, and, if Memory is on, short snippets used to find to-dos and build digests. Requests go through Xeve's service to a provider that doesn't keep data, and every request is logged on your Mac so you can check. See <a href="/privacy">Privacy</a>.`],
    ["Can I pause or delete what Memory has stored?", `Yes. You can pause it, forget a recent stretch of time, forget one app, or delete everything. A small indicator in the notch shows when Memory is on.`],
    ["Does the app have analytics?", `No. The Gobbl app has no analytics. This website uses Google Analytics to count visits.`]
  ],
  "AI agents": [
    ["How does the Claude Code link work?", `Clicking Connect in Gobbl's settings adds a small hook to Claude Code's settings (backed up first). Events go to Gobbl over a private socket on your Mac. If Gobbl isn't running, or you don't answer a prompt within 30 seconds, Claude asks in the terminal as usual.`],
    ["Does it work with Codex?", `Yes, for status: Gob works along while Codex runs and celebrates when it's done. Allow and Deny from the notch is for Claude Code.`],
    ["What is the MCP connector?", `Part of the Memory beta. One switch in Settings, AI Agents ("Connect AI apps automatically") registers Gobbl's MCP helper with Claude Code, Claude Desktop, Codex (which also covers the ChatGPT desktop app), Cursor, VS Code, Windsurf, Gemini CLI, LM Studio and Zed. Those apps can search your memory, read a day, list to-dos and look up people and projects; through the running app they can also read the clipboard, add a reminder or mark a to-do done. Answers cite their sources, and each call is logged on your Mac by tool name and time only. Any other MCP app can use the copyable command.`]
  ]
};
const strip = s => s.replace(/<[^>]+>/g, "");
export const faqHTML = list => list.map(([q, a]) => `<details class="reveal"><summary><h3>${q}</h3></summary><p>${a}</p></details>`).join("\n");
export const faqLD = list => ({ "@context": "https://schema.org", "@type": "FAQPage", mainEntity: list.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: strip(a) } })) });
export const HOME_FAQ = [FAQ.General[0], FAQ.General[1], FAQ["Writing and dictation"][1], FAQ["Memory and privacy"][0], FAQ["AI agents"][0], FAQ.General[2]];

/* ---------- JSON-LD ---------- */
export const orgLD = { "@context": "https://schema.org", "@type": "Organization", "@id": "https://xeve.io/#org", name: "Xeve", url: "https://xeve.io", logo: `${ORIGIN}/img/icon.png`, sameAs: ["https://github.com/xeveio"] };
export const websiteLD = { "@context": "https://schema.org", "@type": "WebSite", "@id": `${ORIGIN}/#website`, name: "Gobbl", url: `${ORIGIN}/`, publisher: { "@id": "https://xeve.io/#org" } };
export const appLD = {
  "@context": "https://schema.org", "@type": "SoftwareApplication", "@id": `${ORIGIN}/#app`, name: "Gobbl",
  description: "A free, open-source notch app for Mac with a pet mascot: file shelf, clipboard history, Now Playing, HUDs, on-device Whisper dictation, AI writing in any app, Claude Code status and approvals, and opt-in screen memory.",
  applicationCategory: "UtilitiesApplication", applicationSubCategory: "Productivity", operatingSystem: "macOS", softwareRequirements: "macOS 14 or later; dictation requires Apple silicon",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" }, isAccessibleForFree: true,
  downloadUrl: `${GH}/releases`, installUrl: `${GH}/releases`, url: `${ORIGIN}/`, image: `${ORIGIN}/og.png`, screenshot: `${ORIGIN}/og.png`,
  license: `${GH}/blob/main/LICENSE`, codeRepository: GH,
  author: { "@id": "https://xeve.io/#org" }, publisher: { "@id": "https://xeve.io/#org" },
  featureList: ["Drag-and-drop file shelf with file tools", "Clipboard history (Shift-Command-Space)", "Now Playing with lyrics", "Volume, brightness and Caps Lock HUDs", "Calendar with Join links", "Focus timer and keep-awake", "Pet mascot with moods, hats, streaks and skins", "Claude Code and Codex status with Allow/Deny from the notch", "Write and rewrite in any text field with the Gobbl key", "On-device Whisper dictation with no word cap", "Chat, reminders, morning brief and evening wrap", "Opt-in screen memory with automatic to-dos, day digests and a timeline (beta)", "On-device search by meaning", "MCP connector for Claude Code, Claude Desktop, Codex, Cursor, VS Code, Windsurf, Gemini CLI, LM Studio and Zed"]
};

/* ---------- shared demo markup ---------- */
export const DICTATE_DEMO = `<div class="dk" data-demo="dictate">
  <div class="dk-panel reveal">
    <div class="skel"></div>
    <canvas class="dk-wave" width="880" height="220" aria-hidden="true"></canvas>
    <button class="dk-hold" type="button" aria-pressed="false">${ic("mic")}Hold to talk</button>
    <p class="dk-hint">Press and hold, or hold Space while the button is focused. In the app it's the right Option key.</p>
  </div>
  <div class="dk-panel reveal" style="--i:1">
    <div class="seg dk-seg" role="group" aria-label="Clean-up level"><button type="button" data-l="verbatim" aria-pressed="false">Verbatim</button><button type="button" data-l="light" aria-pressed="true">Light</button><button type="button" data-l="polish" aria-pressed="false">Polish with AI</button></div>
    <p class="dk-out" aria-live="polite">So I think we should ship the update on Friday and then tell the beta testers.</p>
    <p class="dk-meta">Transcribed on your Mac in about 0.5 s</p>
  </div>
</div>`;

export const TODOS_DEMO = `<div class="todos" data-demo="todos">
  <div class="proof in" role="status">${ic("eye")}<span>Seen in Chrome: <b>"Payment successful"</b> on stripe.com</span></div>
  <p class="fh">To-dos Gobbl found</p>
  <div class="todo done"><input type="checkbox" checked aria-label="Pay the Studio North invoice"><div><b>Pay the Studio North invoice</b><small>From Mail, 12 Sep. Why: "Please pay by Friday" in an email from Studio North.</small><span class="auto">${ic("check")}Ticked off automatically <button class="undo" type="button">Undo</button></span></div></div>
  <div class="todo"><input type="checkbox" aria-label="Send Priya the Q3 launch deck"><div><b>Send Priya the Q3 launch deck</b><small>From Slack. Why: you wrote "I'll send it tomorrow".</small></div></div>
  <div class="todo"><input type="checkbox" aria-label="Book the dentist"><div><b>Book the dentist</b><small>From Messages. Why: Mum asked "did you book it?"</small></div></div>
</div>`;

const node = (x, y, cls, name, role, info, merge) => `<button type="button" class="node ${cls}" style="left:${x}%;top:${y}%" data-name="${name}" data-role="${role}" data-info="${info}"${merge ? ` data-merge="${merge}"` : ""}>${cls.includes("proj") ? ic("layers") : cls.includes("me") ? "" : ic("user")}${name}</button>`;
const MERGE = "Priya Shah in Slack and P. Shah in Mail look like one person.";
export const PEOPLE_DEMO = `<div class="people" data-demo="people">
  <div class="graph reveal">
    <div class="skel"></div>
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
      <line x1="50" y1="50" x2="24" y2="24"/><line x1="50" y1="50" x2="78" y2="22"/><line x1="50" y1="50" x2="78" y2="68"/><line x1="50" y1="50" x2="42" y2="86"/>
      <line x1="24" y1="24" x2="78" y2="68"/><line x1="24" y1="24" x2="42" y2="86"/><line x1="78" y1="22" x2="78" y2="68"/><line class="dash" x1="24" y1="24" x2="16" y2="60"/>
    </svg>
    ${node(50, 50, "me", "You", "That's you", "Every card here is built from text on your screen, on your Mac.")}
    ${node(24, 24, "", "Priya Shah", "Design lead, Studio North", "Seen in Slack, Mail and Figma. Works with you on the Q3 launch.", MERGE)}
    ${node(16, 60, "dup", "P. Shah", "From Mail", "Signs emails as P. Shah, from the Studio North domain.", MERGE)}
    ${node(78, 22, "", "Arjun Rao", "Engineer, Q3 launch", "Mostly in Slack. Last talked about the release checklist yesterday.")}
    ${node(78, 68, "proj", "Q3 launch", "Project", "People: Priya, Arjun. Open to-do: send the deck. Mentioned 14 times this week.")}
    ${node(42, 86, "proj", "Studio North", "Company", "Priya works here. Their invoice was paid and ticked off automatically.")}
  </div>
  <div class="pcard reveal" style="--i:1" aria-live="polite"><b>Priya Shah</b><span>Design lead, Studio North</span><p>Seen in Slack, Mail and Figma. Works with you on the Q3 launch.</p><div class="merge"><em>Same person?</em> ${MERGE}<span class="mb"><button type="button">Merge</button><button type="button">Keep apart</button></span></div></div>
</div>`;

export const MEMCHAT = `<div class="memchat">
  <p class="q">When is the Studio North invoice due, and did I pay it?</p>
  <p class="a">It was due Friday, 18 September, and you paid it on 14 September.<sup>1</sup> <sup>2</sup></p>
  <ol class="src"><li>${ic("globe")}Mail, 12 Sep: "Invoice 0142 from Studio North"</li><li>${ic("globe")}Chrome, 14 Sep: stripe.com, "Payment successful"</li></ol>
</div>`;

export const DEMO_CSS = `
.seg{display:inline-flex;flex-wrap:wrap;padding:4px;border-radius:999px;background:var(--bg2);border:1px solid var(--line)}
.seg button{padding:8px 16px;border-radius:999px;font-weight:650;font-size:14.5px;color:var(--muted);transition:all .25s var(--ease)}
.seg button[aria-pressed=true],.seg button.on{background:var(--lime);color:#07120a}
/* dictation */
.dk{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:stretch}
.dk-panel{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:24px;padding:24px}
.dk-wave{width:100%;height:auto;aspect-ratio:4/1;display:block}
.dk-hold{width:100%;margin-top:16px;padding:16px;border-radius:14px;background:rgba(166,242,92,.1);border:1px solid rgba(166,242,92,.3);color:var(--lime);font-weight:750;display:flex;gap:10px;justify-content:center;align-items:center;user-select:none;-webkit-user-select:none;touch-action:none;transition:background .2s,color .2s,transform .15s}
.dk-hold.down{background:var(--lime);color:#07120a;transform:scale(.98)}
.dk-hint{font-size:13px;color:var(--faint);margin:12px 0 0;text-align:center}
.dk-out{min-height:5.2em;font-size:clamp(18px,1.9vw,22px);line-height:1.45;margin:22px 0 10px;letter-spacing:-.01em}
.dk-out.working{color:var(--faint)}.dk-out.working::after{content:"";display:inline-block;width:9px;height:1em;margin-left:4px;background:var(--lime);vertical-align:-2px;animation:blink 1s steps(1) infinite}
.dk-out.ai{color:#e6f9d3}
.dk-meta{font-size:13.5px;color:var(--faint);margin:0}
@keyframes blink{50%{opacity:0}}
/* to-dos */
.todos{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:24px;padding:22px 18px 12px}
.todos .fh{padding:0 12px}
.todo{display:grid;grid-template-columns:auto 1fr;gap:12px;padding:12px;border-radius:14px;transition:background .4s}
.todo+.todo{border-top:1px solid var(--line);border-radius:0}
.todo input{appearance:none;-webkit-appearance:none;width:21px;height:21px;border-radius:7px;border:1.5px solid var(--faint);margin:3px 0 0;display:grid;place-items:center;cursor:pointer;transition:background .3s,border-color .3s}
.todo input:checked{background:var(--lime);border-color:var(--lime)}
.todo input:checked::after{content:"";width:9px;height:5px;border-left:2px solid #07120a;border-bottom:2px solid #07120a;transform:translateY(-1px) rotate(-45deg)}
.todo b{font-weight:620;transition:color .4s}.todo.done b{color:var(--faint);text-decoration:line-through;text-decoration-color:var(--faint)}
.todo small{display:block;color:var(--muted);font-size:13.5px;line-height:1.45;margin-top:2px}
.todo .auto{display:none;gap:6px;align-items:center;color:var(--lime);font-size:13px;font-weight:650;margin-top:6px}
.todo.done .auto{display:flex}.todo.done{background:rgba(166,242,92,.05)}
.undo{color:var(--text);text-decoration:underline;text-underline-offset:3px;font-size:13px;margin-left:6px}
.proof{position:absolute;right:16px;top:-20px;display:flex;gap:8px;align-items:center;max-width:calc(100% - 32px);padding:8px 14px;border-radius:999px;background:#1d2a17;border:1px solid rgba(166,242,92,.35);color:var(--soft);font-size:13px;box-shadow:0 14px 30px -12px #000;opacity:0;transform:translateY(8px) scale(.96);transition:opacity .4s,transform .5s var(--spring)}
.proof .i{color:var(--lime)}.proof.in{opacity:1;transform:none}
/* people graph */
.people{display:grid;grid-template-columns:1.5fr 1fr;gap:16px;align-items:stretch}
.graph{position:relative;aspect-ratio:16/11;border-radius:24px;border:1px solid var(--line);background:radial-gradient(circle at 50% 50%,rgba(166,242,92,.08),transparent 60%),var(--surface);overflow:hidden}
.graph>svg{position:absolute;inset:0;width:100%;height:100%}
.graph line{stroke:rgba(255,255,255,.14);stroke-width:1.2;vector-effect:non-scaling-stroke}
.graph line.dash{stroke:rgba(245,197,66,.5);stroke-dasharray:4 4}
.node{position:absolute;transform:translate(-50%,-50%);display:flex;gap:6px;align-items:center;padding:7px 12px;border-radius:999px;background:var(--raised);border:1px solid var(--line2);font-size:13.5px;font-weight:650;white-space:nowrap;transition:border-color .25s,box-shadow .25s,transform .3s var(--spring)}
.node .i{color:var(--muted);width:14px;height:14px}
.node:hover,.node.on{border-color:var(--lime);box-shadow:0 0 0 4px rgba(166,242,92,.12);transform:translate(-50%,-50%) scale(1.05)}
.node.me{background:var(--lime);color:#07120a;border-color:var(--lime)}
.node.proj{border-radius:10px}.node.proj .i{color:var(--gold)}
.node.dup{border-style:dashed;border-color:rgba(245,197,66,.6)}
.pcard{background:var(--surface);border:1px solid var(--line);border-radius:24px;padding:24px;min-height:100%}
.pcard b{display:block;font-size:22px;letter-spacing:-.02em}
.pcard span{color:var(--lime);font-size:14px;font-weight:600}
.pcard p{color:var(--muted);font-size:15px}
.merge{margin-top:14px;padding:12px 14px;border-radius:14px;background:rgba(245,197,66,.07);border:1px solid rgba(245,197,66,.28);font-size:14px;color:var(--soft)}
.merge em{font-style:normal;font-weight:700;color:var(--gold);display:block;margin-bottom:2px}
.merge .mb{display:flex;gap:8px;margin-top:10px}
.merge button{padding:6px 12px;border-radius:999px;background:rgba(255,255,255,.08);font-size:13px;font-weight:650}
.merge button:first-of-type{background:var(--gold);color:#1a1405}
/* memory chat */
.memchat{background:var(--surface);border:1px solid var(--line);border-radius:24px;padding:22px}
.memchat .q{margin:0 0 10px auto;width:fit-content;max-width:85%;background:var(--lime);color:#07120a;padding:9px 14px;border-radius:16px 16px 4px 16px;font-size:15px;font-weight:550}
.memchat .a{margin:0;background:rgba(255,255,255,.07);padding:11px 14px;border-radius:16px 16px 16px 4px;width:fit-content;max-width:90%;font-size:15px}
.memchat sup{color:var(--lime);font-weight:700;margin-left:2px}
.memchat .src{list-style:none;padding:0;margin:14px 0 0;display:grid;gap:6px;font-size:13px;color:var(--muted)}
.memchat .src li{display:flex;gap:8px;align-items:center;counter-increment:src}
.memchat .src li::before{content:counter(src);font-weight:700;color:var(--lime);width:14px}
@media (max-width:900px){.dk,.people{grid-template-columns:1fr}}
@media (max-width:560px){.node{font-size:11.5px;padding:5px 9px}.node .i{display:none}.graph{aspect-ratio:1/1}.proof{position:static;margin-bottom:12px;border-radius:14px}}
`;

/* ---------- subpage frame ---------- */
export function subpage({ kicker, h1, lede, meta, pet, toc, content, cta = true }) {
  return `<section class="phero"><div class="wrap"><div class="grid">
  <div>
    <div class="kicker">${kicker}</div>
    <h1>${h1}</h1>
    <p class="lede">${lede}</p>
    ${cta ? `<div class="cta"><a class="btn primary magnetic" href="/download">${ic("download")}Download for Mac</a><a class="btn ghost magnetic" href="${GH}">${ic("github")}View on GitHub</a></div>` : ""}
    ${meta ? `<div class="meta-row">${meta.map(([i, t]) => `<span>${ic(i)}${t}</span>`).join("")}</div>` : ""}
  </div>
  <div class="pet"><canvas width="440" height="440" data-gob='${JSON.stringify(pet || { char: "retro" })}' role="img" aria-label="Gob, the Gobbl pet, a small retro computer with a face on its screen"></canvas></div>
</div></div></section>
<div class="wrap page">
  <article class="prose">${content}</article>
  <aside class="aside">
    ${toc ? `<nav class="box toc" aria-label="On this page"><p class="fh">On this page</p>${toc.map(([id, t]) => `<a href="#${id}">${t}</a>`).join("")}</nav>` : ""}
    <div class="box"><p>Free and open source for macOS 14+. No account.</p><a class="btn primary" href="/download">${ic("download")}Download Gobbl</a></div>
  </aside>
</div>`;
}
export const related = links => `<h2 id="related">Related</h2><div class="grid2">${links.map(([u, t, d]) => `<a class="tile2" href="${u}"><h3>${t}${ic("arrow")}</h3><p>${d}</p></a>`).join("")}</div>`;
