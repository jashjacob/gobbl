// POST /api/support-checkout → a fresh Dodo Payments checkout session for "Support Gobbl"
// (pay what you want, $20 suggested). The download dialog (site/js/site.js) embeds it inline.
// Cloudflare Pages Function on the "gobbl" project, deployed by scripts/deploy-site.sh.
// Secret (once): wrangler pages secret put DODO_API_KEY --project-name gobbl
// Optional vars for a test deploy: DODO_API_BASE=https://test.dodopayments.com, DODO_PRODUCT_ID.
const LIVE_PRODUCT = "pdt_0NndKfZ0bejwqwSDQYi5f";

export async function onRequestPost({ env, request }) {
  if (!env.DODO_API_KEY) return json({ error: "checkout not configured" }, 503);
  const base = env.DODO_API_BASE || "https://live.dodopayments.com";
  const origin = new URL(request.url).origin;
  // Pay-what-you-want sessions must carry the amount (US cents): $1–$1,000, $20 by default.
  const { amount: raw } = await request.json().catch(() => ({}));
  const amount = raw === undefined ? 2000 : Math.round(Number(raw));
  if (!Number.isFinite(amount) || amount < 100 || amount > 100000) return json({ error: "amount must be $1 to $1,000" }, 400);
  const r = await fetch(`${base}/checkouts`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.DODO_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      product_cart: [{ product_id: env.DODO_PRODUCT_ID || LIVE_PRODUCT, quantity: 1, amount }],
      return_url: `${origin}/thanks`,
      customization: { theme: "dark" },
    }),
  });
  if (!r.ok) return json({ error: "checkout unavailable" }, 502);
  const { checkout_url } = await r.json();
  return json({ checkout_url, mode: base.includes("test.") ? "test" : "live" });
}

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
