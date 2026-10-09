#!/usr/bin/env bash
# Iris — "Remove tracking from links" switch (jegly 2026-10-09; idea from his www browser's LinkSanitizer; verified
# against 156.0.8078.11). Needs apply-tracking-param-strip.sh, apply-shredder.sh (pref
# iris.privacy.strip_tracking_params, default ON, registered in iris_shredder.cc), apply-iris-hardening-page.sh,
# apply-android-iris-privacy-settings.sh.
#   - the interceptor (patches/src/chrome/browser/ssl/iris_tracking_param_interceptor.cc) reads the pref per navigation
#     and now also strips mc_cid, s_kwcid, _openstat, hsCtaTracking, __hssc, __hstc, originalSub, ref_src, ref_url.
#     Bare "ref" is NOT stripped (load-bearing, e.g. GitHub ?ref=); a per-site exception is still to do.
#   - desktop: toggle on Settings -> Privacy and security -> Iris hardening (group "Ads and trackers")
#   - Android: switch in the "Ads and trackers" group of Privacy and security
# STATUS 2026-10-09: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in iris_tracking_param_interceptor.cc; do
  from="$DIR/src/chrome/browser/ssl/$f"; to="chrome/browser/ssl/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
KEY = "iris.privacy.strip_tracking_params"
TITLE = "Remove tracking from links"
SUB = ("Removes utm_*, fbclid, gclid and similar tracking parameters from web addresses before the page loads. "
       "Turn it off if a link stops working.")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % KEY,
     "\"%s\"" % KEY, "allowlist")
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
hs = open(H).read()
A = "<h2>Ads and trackers</h2>\n"
if A not in hs: die(H + ": 'Ads and trackers' group not found (run apply-iris-hardening-page.sh first)")
edit(H, A,
     A + "  <settings-toggle-button id=\"irisStripTrackingToggle\" class=\"hr\"\n"
         "      pref-key=\"%s\"\n"
         "      label=\"%s\"\n"
         "      sub-label=\"%s\">\n"
         "  </settings-toggle-button>\n" % (KEY, TITLE, SUB),
     "irisStripTrackingToggle", "desktop toggle")
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
sw = ("        ChromeSwitchPreference irisStripTracking =\n"
      "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
      "        irisStripTracking.setKey(\"iris_strip_tracking\");\n"
      "        irisStripTracking.setPersistent(false);\n"
      "        irisStripTracking.setTitle(\"%s\");\n"
      "        irisStripTracking.setSummary(\n"
      "                \"%s\");\n"
      "        irisStripTracking.setChecked(\n"
      "                UserPrefs.get(getProfile()).getBoolean(\"%s\"));\n"
      "        irisStripTracking.setOnPreferenceChangeListener(\n"
      "                (preference, newValue) -> {\n"
      "                    UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);\n"
      "                    return true;\n"
      "                });\n"
      "        irisCategory.addPreference(irisStripTracking);\n") % (TITLE, SUB, KEY, KEY)
edit(J, "        irisCategory.addPreference(irisJitEverywhere);\n",
     sw + "        irisCategory.addPreference(irisJitEverywhere);\n",
     "irisStripTracking =", "Android switch")
edit(J, '{"Ads and trackers", "iris_block_ads", "iris_adblock_extra"}',
     '{"Ads and trackers", "iris_block_ads", "iris_adblock_extra", "iris_strip_tracking"}',
     '"iris_strip_tracking"}', "Android group")
PY
echo "=== tracking-parameter switch complete ==="
