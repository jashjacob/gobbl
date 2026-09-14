import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "fs";
import { execSync } from "child_process";
const SITE = new URL("../../site", import.meta.url).pathname.replace(/\/$/, "");
const walk = d => readdirSync(d).flatMap(f => { const p = d + "/" + f; return statSync(p).isDirectory() ? walk(p) : [p]; });
const files = walk(SITE).filter(f => f.endsWith(".html"));
let bad = 0; const titles = new Map(), descs = new Map();
const resolve = href => {
  let p = href.split("#")[0].split("?")[0]; if (!p) return true;
  if (p === "/download") return true;
  if (p.endsWith("/")) p += "index.html";
  const f = SITE + p; return existsSync(f) || existsSync(f + ".html");
};
for (const f of files) {
  const h = readFileSync(f, "utf8"), rel = f.replace(SITE, ""), issues = [];
  const h1 = (h.match(/<h1[\s>]/g) || []).length; if (h1 !== 1) issues.push("h1 count " + h1);
  const t = h.match(/<title>(.*?)<\/title>/)?.[1], d = h.match(/name="description" content="(.*?)"/)?.[1];
  if (!rel.includes("verify")) {
    if (titles.has(t)) issues.push("dup title"); titles.set(t, rel);
    if (descs.has(d)) issues.push("dup desc"); descs.set(d, rel);
    if (!/rel="canonical"/.test(h)) issues.push("no canonical");
    if (!/og:image/.test(h)) issues.push("no og");
    if (!/G-21SSB74NQD/.test(h)) issues.push("no GA");
  }
  [...h.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].forEach(m => { try { const o = JSON.parse(m[1]); issues.push("LD:" + o["@type"]); } catch (e) { issues.push("LD PARSE ERROR " + e.message); bad++; } });
  [...h.matchAll(/<script(?![^>]*\bsrc=)(?![^>]*ld\+json)[^>]*>([\s\S]*?)<\/script>/g)].forEach((m, i) => { const tmp = `/tmp/claude-501/chk.js`; try { writeFileSync(tmp, m[1]); execSync(`node --check ${tmp}`, { stdio: "pipe" }); } catch (e) { issues.push("INLINE JS ERROR " + e.stderr); bad++; } });
  [...h.matchAll(/href="(\/[^"]*)"/g)].forEach(m => { if (!resolve(m[1])) { issues.push("BROKEN " + m[1]); bad++; } });
  [...h.matchAll(/src="(\/[^"?]*)/g)].forEach(m => { if (!resolve(m[1])) { issues.push("BROKEN src " + m[1]); bad++; } });
  [...h.matchAll(/href="#([^"]+)"/g)].forEach(m => { if (!h.includes(`id="${m[1]}"`)) { issues.push("BROKEN anchor #" + m[1]); bad++; } });
  [...h.matchAll(/<img\b[^>]*>/g)].forEach(m => { if (!/\balt=/.test(m[0])) { issues.push("img no alt"); bad++; } });
  // heading order: no skipping levels
  let prev = 0; [...h.matchAll(/<h([1-6])[\s>]/g)].forEach(m => { const l = +m[1]; if (prev && l > prev + 1) issues.push(`h${prev}->h${l}`); prev = l; });
  console.log(rel.padEnd(28), `title ${t?.length} desc ${d?.length}`, issues.join("; "));
}
// cross-page anchors like /features#key
console.log(bad ? `FAILURES: ${bad}` : "no hard failures");
