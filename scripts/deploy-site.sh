#!/bin/bash
set -euo pipefail

# Deploy the marketing site (site/) to Cloudflare Pages project "gobbl",
# served at https://gobbl.xeve.io.
#
# Usage: scripts/deploy-site.sh [--preview]
#
# If a notarized DMG exists in build/release/ (from scripts/release.sh), it is
# bundled at /download/Gobbl-<version>.dmg and /download redirects to it.
# Otherwise /download redirects to the Sparkle channel's latest DMG.
#
# First deploy: create the Pages project and the gobbl.xeve.io custom domain
# (xeve.io lives in the Kvyn.14 account; see ~/.claude/CLAUDE.md).
# Credentials: CF_XEVE_API_TOKEN + CF_XEVE_ACCOUNT_ID in ~/.secrets/cloudflare.env.

BRANCH=main
[ "${1:-}" = "--preview" ] && BRANCH=preview

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/site-dist"
cd "$ROOT"

rm -rf "$OUT"
cp -R site "$OUT"
find "$OUT" -name .DS_Store -delete

# Cache-bust images: /img/x.png?v=<content hash>.
V=$(cat site/img/*.png 2>/dev/null | shasum | cut -c1-10)
perl -pi -e "s/__V__/$V/g" "$OUT/index.html"

DMG=$(ls -t build/release/Gobbl-*.dmg 2>/dev/null | head -1 || true)
# Only ever ship a notarized, stapled image from the website (a --skip-notarize dry run isn't).
if [ -n "$DMG" ] && ! xcrun stapler validate -q "$DMG" 2>/dev/null; then
  echo "Skipping $DMG: not notarized/stapled"
  DMG=""
fi
if [ -n "$DMG" ]; then
  VERSION=$(basename "$DMG" .dmg | sed 's/^Gobbl-//')
  mkdir -p "$OUT/download"
  cp "$DMG" "$OUT/download/"
  printf '/download /download/%s 302\n' "$(basename "$DMG")" > "$OUT/_redirects"
  perl -pi -e "s#(data-version>)[^<]*#\${1}v$VERSION#g" "$OUT/index.html"
  echo "Bundling $(basename "$DMG")"
else
  # Before the first release /download goes to GitHub; after it, to the Sparkle channel's latest DMG.
  if curl -fsIo /dev/null --max-time 10 https://dl.xeve.io/gobbl/Gobbl-latest.dmg; then
    printf '/download https://dl.xeve.io/gobbl/Gobbl-latest.dmg 302\n' > "$OUT/_redirects"
    echo "No local DMG; /download → dl.xeve.io"
  else
    printf '/download https://github.com/xeveio/gobbl 302\n' > "$OUT/_redirects"
    echo "No release yet; /download → GitHub"
  fi
fi

# /support → Dodo Payments checkout for "Support Gobbl" (pay what you want, $20 suggested,
# one time). Live product; the test-mode twin is pdt_0NndI2JAsENYxqUNdCoC7 on test.checkout.
SUPPORT_URL="${GOBBL_SUPPORT_URL:-https://checkout.dodopayments.com/buy/pdt_0NndKfZ0bejwqwSDQYi5f?quantity=1&redirect_url=https://gobbl.xeve.io/thanks}"
printf '/support %s 302\n' "$SUPPORT_URL" >> "$OUT/_redirects"

cat > "$OUT/_headers" <<'HEADERS'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
  Permissions-Policy: camera=(), microphone=(), geolocation=()
/img/*
  Cache-Control: public, max-age=86400
/download/*
  Content-Type: application/x-apple-diskimage
  Content-Disposition: attachment
  Cache-Control: public, max-age=3600
HEADERS

CLOUDFLARE_API_TOKEN="$(grep '^CF_XEVE_API_TOKEN=' ~/.secrets/cloudflare.env | cut -d= -f2-)" \
CLOUDFLARE_ACCOUNT_ID="$(grep '^CF_XEVE_ACCOUNT_ID=' ~/.secrets/cloudflare.env | cut -d= -f2-)" \
  wrangler pages deploy "$OUT" --project-name gobbl --branch "$BRANCH" --commit-dirty=true
