import { spawn } from "child_process"; import { mkdtempSync } from "fs"; import { tmpdir } from "os";
const port = 9900 + Math.floor(Math.random() * 90), wait = ms => new Promise(r => setTimeout(r, ms));
const proc = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", ["--headless=new", "--disable-gpu", `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(tmpdir() + "/cdpf")}`, "about:blank"], { stdio: "ignore" });
let list; for (let i = 0; i < 50; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === "page")) break; } catch {} await wait(200); }
const ws = new WebSocket(list.find(t => t.type === "page").webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const pend = new Map(); ws.onmessage = e => { const m = JSON.parse(e.data); if (pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Emulation.setDeviceMetricsOverride", { width: 500, height: 900, deviceScaleFactor: 1, mobile: true });
await send("Page.navigate", { url: "http://127.0.0.1:8765/index.html?static" }); await wait(4000);
const expr = `(() => { const W = document.documentElement.clientWidth, out = [];
  for (const el of document.querySelectorAll("body *")) { const r = el.getBoundingClientRect(); if (r.width && r.right > W + 1) {
    let p = el.parentElement, clipped = false; while (p && p !== document.body) { const o = getComputedStyle(p).overflowX; if (o === "hidden" || o === "auto" || o === "scroll" || o === "clip") { const pr = p.getBoundingClientRect(); if (pr.right <= W + 1) { clipped = true; break; } } p = p.parentElement; }
    if (!clipped) out.push((el.tagName + "." + [...el.classList].join(".")) + " right=" + Math.round(r.right) + " w=" + Math.round(r.width) + " in " + (el.closest("section,header,nav,div.marquee")?.id || el.closest("section,header,nav,div")?.className || "")); } }
  return "clientWidth=" + W + " scrollWidth=" + document.documentElement.scrollWidth + "\\n" + out.slice(0, 25).join("\\n"); })()`;
console.log((await send("Runtime.evaluate", { expression: expr, returnByValue: true })).result.result.value);
ws.close(); proc.kill();
