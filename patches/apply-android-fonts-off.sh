#!/usr/bin/env bash
# Iris — Android: no web-font lookups through Play services (issue #1 item 4, jegly 2026-11-05).
# Verified against 157.0.8103.38 (gitiles copies, 2026-11-05): a CSS local() font that is not a firmware font goes
# from Blink's FontUniqueNameLookupAndroid to the browser's AndroidFontLookupImpl.tryFetchFont(), which asks
# com.google.android.gms.fonts through FontsContractCompat. That path does not check ChromiumPlayServicesAvailability,
# so apply-android-no-gms.sh does not stop it. Blink only connects to that service (and only builds the downloadable
# font table, a fingerprinting surface) while RuntimeEnabledFeatures::AndroidDownloadableFontsMatchingEnabled(),
# which content/child/runtime_features.cc maps from features::kAndroidDownloadableFontsMatching. That base::Feature is
# in content/common/features.cc (NOT content/public/common/content_features.cc as the issue said), on by default.
# Off: firmware (on-device) fonts still match; nothing is fetched.
# STATUS 2026-11-05: copy-tested on a 157 file copy, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
grep -q '"AndroidDownloadableFontsMatching",' content/child/runtime_features.cc \
  || { echo "ERROR: runtime_features.cc no longer maps AndroidDownloadableFontsMatching (drift?)" >&2; exit 1; }
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("content/common/features.cc",
     "BASE_FEATURE(kAndroidDownloadableFontsMatching,\n"
     "             base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "// Iris (apply-android-fonts-off): no font lookups through Play services.\n"
     "BASE_FEATURE(kAndroidDownloadableFontsMatching,\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);\n",
     "// Iris (apply-android-fonts-off)", "downloadable fonts off")
PY
echo "=== Android downloadable fonts off complete ==="
