// Full-page screenshots over the Chrome DevTools protocol (Node's built-in WebSocket).
// Usage: node shot.mjs <outdir> <base> <path1> [path2 ...]   (each shot at 1440 and 500, plain and ?static)
import { spawn } from "child_process";
import { writeFileSync, mkdtempSync } from "fs";
import { tmpdir } from "os";
const [outDir, base, ...paths] = process.argv.slice(2);
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9400 + Math.floor(Math.random() * 400);
const proc = spawn(CHROME, ["--headless=new", "--disable-gpu", "--hide-scrollbars", `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(tmpdir() + "/cdp")}`, "about:blank"], { stdio: "ignore" });
const wait = ms => new Promise(r => setTimeout(r, ms));
let list;
for (let i = 0; i < 50; i++) { try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find(t => t.type === "page")) break; } catch {} await wait(200); }
const ws = new WebSocket(list.find(t => t.type === "page").webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pending = new Map(), listeners = [];
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else listeners.forEach(f => f(m)); };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Page.enable"); await send("Runtime.enable");
let errors = [];
listeners.push(m => {
  if (m.method === "Runtime.exceptionThrown") errors.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
  if (m.method === "Runtime.consoleAPICalled" && m.params.type === "error") errors.push(m.params.args.map(a => a.value || a.description).join(" "));
});
for (const path of paths) for (const width of [1440, 500]) for (const mode of ["", "static"]) {
  errors = [];
  await send("Emulation.setDeviceMetricsOverride", { width, height: 900, deviceScaleFactor: 1, mobile: width < 600 });
  const url = base + path + (mode ? (path.includes("?") ? "&" : "?") + "static" : "");
  const loaded = new Promise(r => { const f = m => { if (m.method === "Page.loadEventFired") { listeners.splice(listeners.indexOf(f), 1); r(); } }; listeners.push(f); });
  await send("Page.navigate", { url }); await loaded; await wait(1500);
  const h = (await send("Runtime.evaluate", { expression: "document.documentElement.scrollHeight", returnByValue: true })).result.result.value;
  // A viewport as tall as the page, so every lazy section counts as on screen.
  await send("Emulation.setDeviceMetricsOverride", { width, height: Math.min(h, 16000), deviceScaleFactor: 1, mobile: width < 600 });
  await wait(mode ? 2500 : 4000);
  const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: { x: 0, y: 0, width, height: h, scale: 1 } });
  const name = `${outDir}/${(path.replace(/^\//, "").replace(/\.html$/, "").replace(/\//g, "_") || "index")}-${width}${mode ? "-static" : ""}.png`;
  writeFileSync(name, Buffer.from(shot.result.data, "base64"));
  const sw = (await send("Runtime.evaluate", { expression: "document.documentElement.scrollWidth", returnByValue: true })).result.result.value;
  console.log(name, h + "px", sw > width ? "OVERFLOW " + sw : "no-overflow", errors.length ? "ERRORS: " + errors.join(" | ") : "ok");
}
ws.close(); proc.kill();
