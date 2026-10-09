#!/usr/bin/env bash
# Iris — "Block third-party requests" switch (jegly 2026-10-09; idea from his www browser; verified against
# 156.0.8078.11). Profile pref iris.privacy.block_third_party (iris_shredder.cc), OFF by default. When on, a page's
# subresource requests (images, scripts, styles, fonts, fetch/XHR, ...) to a different site than the top-level page are
# refused in the renderer with ERR_BLOCKED_BY_CLIENT (ResourceRequestBlockedReason::kOther), the same place the ad blocker
# and CSP refuse requests: BaseFetchContext::CanRequestInternal. "Site" = schemeful site (SecurityOrigin::IsSameSiteWith).
# Not blocked: page and frame navigations (links, iframes, login redirects), and requests made by workers.
# Per-site exemption: "Allow ads" for the site from the lock icon (the browser answers false for that site).
# Plumbing: new sync method IrisFingerprintHost.GetBlockThirdParty() (mojom in patches/src, copied by
# apply-fingerprint.sh), asked once per document on its first third-party request and cached (applies to pages opened
# after the switch is changed).
# Many sites break (CDNs, fonts, embedded media, logins that load scripts from another domain). Off by default.
# Desktop: Settings -> Privacy and security -> Iris hardening -> Ads and trackers. Android: same group.
# Needs apply-fingerprint.sh (copies the updated mojom/helper/host), apply-shredder, apply-iris-hardening-page,
# apply-android-iris-privacy-settings. STATUS 2026-10-09: copy-tested only, NOT compile-proven (mojom + Blink core).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in third_party/blink/public/mojom/iris/iris_fingerprint.mojom \
         third_party/blink/renderer/core/html/canvas/iris_fingerprint.h \
         third_party/blink/renderer/core/html/canvas/iris_fingerprint.cc \
         chrome/browser/iris/iris_fingerprint_host.cc; do
  from="$DIR/src/$f"; [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
B = "third_party/blink/renderer/core/loader/base_fetch_context.cc"
edit(B, '#include "third_party/blink/renderer/core/frame/settings.h"\n',
     '#include "third_party/blink/renderer/core/frame/settings.h"\n'
     '#include "third_party/blink/renderer/core/html/canvas/iris_fingerprint.h"  // Iris: block third-party\n',
     'iris_fingerprint.h"  // Iris: block third-party', "include")
edit(B, "  if (type == ResourceType::kScript) {\n    if (!AllowScript()) {\n",
     "  // Iris: Settings -> \"Block third-party requests\" (apply-block-third-party.sh). Cheap checks first; the\n"
     "  // browser is asked once per document.\n"
     "  if (IsFrameContext() && url.ProtocolIsInHttpFamily() &&\n"
     "      request_mode != network::mojom::RequestMode::kNavigate) {\n"
     "    const SecurityOrigin* top_origin = resource_request.TopFrameOrigin();\n"
     "    if (top_origin && (top_origin->Protocol() == \"http\" ||\n          top_origin->Protocol() == \"https\")) {\n"
     "      scoped_refptr<const SecurityOrigin> target = SecurityOrigin::Create(url);\n"
     "      if (!target->IsSameSiteWith(top_origin) &&\n"
     "          IrisFingerprint::ShouldBlockThirdParty(GetExecutionContext())) {\n"
     "        return ResourceRequestBlockedReason::kOther;\n"
     "      }\n"
     "    }\n"
     "  }\n\n"
     "  if (type == ResourceType::kScript) {\n    if (!AllowScript()) {\n",
     "apply-block-third-party.sh", "hook")
KEY = "iris.privacy.block_third_party"
TITLE = "Block third-party requests"
SUB = ("Pages can only load images, scripts, fonts and data from their own site. Stops trackers and ad networks, but "
       "breaks many websites. To allow one site, allow ads for it from the lock icon. Applies to pages opened after you change it.")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % KEY,
     "\"%s\"" % KEY, "allowlist")
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
edit(H, "  <h2>Web content</h2>\n",
     "  <settings-toggle-button id=\"irisBlockThirdPartyToggle\" class=\"hr\"\n"
     "      pref-key=\"%s\"\n"
     "      label=\"%s\"\n"
     "      sub-label=\"%s\">\n"
     "  </settings-toggle-button>\n"
     "  <h2>Web content</h2>\n" % (KEY, TITLE, SUB),
     "irisBlockThirdPartyToggle", "desktop toggle")
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
sw = ("        ChromeSwitchPreference irisBlockThirdParty =\n"
      "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
      "        irisBlockThirdParty.setKey(\"iris_block_third_party\");\n"
      "        irisBlockThirdParty.setPersistent(false);\n"
      "        irisBlockThirdParty.setTitle(\"%s\");\n"
      "        irisBlockThirdParty.setSummary(\n"
      "                \"%s\");\n"
      "        irisBlockThirdParty.setChecked(\n"
      "                UserPrefs.get(getProfile()).getBoolean(\"%s\"));\n"
      "        irisBlockThirdParty.setOnPreferenceChangeListener(\n"
      "                (preference, newValue) -> {\n"
      "                    UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);\n"
      "                    return true;\n"
      "                });\n"
      "        irisCategory.addPreference(irisBlockThirdParty);\n") % (TITLE, SUB, KEY, KEY)
edit(J, "        irisCategory.addPreference(irisJitEverywhere);\n",
     sw + "        irisCategory.addPreference(irisJitEverywhere);\n",
     "irisBlockThirdParty =", "Android switch")
edit(J, '"iris_block_ads", "iris_adblock_extra", "iris_strip_tracking"}',
     '"iris_block_ads", "iris_adblock_extra", "iris_strip_tracking", "iris_block_third_party"}',
     '"iris_block_third_party"}', "Android group")
PY
echo "=== block third-party requests complete ==="
