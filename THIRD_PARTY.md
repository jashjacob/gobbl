# Third-party code

Gobbl is MIT. Every piece of third-party code in this repository is listed
here with its license. GPL code must never be copied in (see README).

| Component | Where | License | Upstream |
|---|---|---|---|
| mediaremote-adapter 0.7.7 | `Vendor/mediaremote-adapter/` (revision in `REVISION`) | BSD 3-Clause (`Vendor/mediaremote-adapter/LICENSE`) | https://github.com/ungive/mediaremote-adapter |
| dodopayments-checkout 1.9.9 | `site/js/vendor/dodo-checkout-1.9.9.js` (website only, not the app) | Apache 2.0 (`site/js/vendor/dodo-checkout-LICENSE.txt`) | https://www.npmjs.com/package/dodopayments-checkout |

The adapter is compiled by `scripts/build-mediaremote.sh` into
`MediaRemoteAdapter.framework`, bundled in `Gobbl.app/Contents/Resources/`
and run through `/usr/bin/perl`; Gobbl does not link against it. The BSD
license requires its copyright notice in the distribution: it is shown in
Settings → About.
