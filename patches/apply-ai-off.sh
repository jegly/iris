#!/usr/bin/env bash
# Iris — no AI features (jegly 2026-10-01: "we dont want any ai features"). Verified against this checkout.
# Already off elsewhere: Gemini/Glic (apply-glic-off.sh, master kill switch), Compose/"Help me write"
# (enable_compose=false), on-device models (use_on_device_model_service=false), the AI settings page
# (apply-remove-ai-page.sh), Touch to Search (apply-vanadium-parity.sh), web AI APIs (Prompt/Writer/Rewriter/
# Summarizer/Translator/LanguageDetector/WebNN in apply-default-switches.sh). Autofill AI needs a signed-in Google
# account (SatisfiesAccountRequirements) and Iris has no Google API keys -> cannot run.
# This script turns off the rest, at each family's master check:
#   1) AI Mode (Google "AIM": omnibox/composebox/Lens AI entry points) — omnibox::kAimEnabled is the documented
#      kill switch of AimEligibilityService::IsAimAllowedByFeatureAndPolicy() -> every AIM entry point is ineligible.
#   2) Gemini Nano through Android AICore — kAICorePrompt is ENABLED in non-Chrome-branded builds -> disabled.
#   3) Read Aloud / "Listen to this page" (Android; Google server TTS of the page) — ReadAloudFeatures.isAllowed().
#   4) Google Lens (Android; sends images/screens to Google) — LensController.isLensEnabled() and
#      LensSupportStatusHelper.isLensSearchSupported(), plus the Lens button on the quick-action search widget.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

def add_const(p, line, label):
    s = open(p).read()
    if line in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    i = s.rstrip().rfind("}")
    if i < 0 or not s.rstrip().endswith("}"): die("%s: class end not found (drift?)" % p)
    open(p, "w").write(s[:i] + "\n" + line + s[i:]); print("OK   %s : %s" % (p, label))

# 1) AI Mode master kill switch
p = "components/omnibox/browser/aim_eligibility_service_features.cc"
new = "BASE_FEATURE(kAimEnabled, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no AI Mode\n"
edit(p, "BASE_FEATURE(kAimEnabled, base::FEATURE_ENABLED_BY_DEFAULT);\n", new, new, "AI Mode off")

# 2) Gemini Nano via Android AICore (non-branded branch)
p = "components/optimization_guide/core/model_execution/android/model_broker_android.cc"
old = ("#else\n"
       "BASE_FEATURE(kAICorePrompt, base::FEATURE_ENABLED_BY_DEFAULT);\n")
new = ("#else\n"
       "BASE_FEATURE(kAICorePrompt, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no AICore/Gemini Nano\n")
edit(p, old, new, new, "AICore prompt off")

# 3) Read Aloud
p = "chrome/browser/readaloud/android/java/src/org/chromium/chrome/browser/readaloud/ReadAloudFeatures.java"
M = "        if (IRIS_NO_READ_ALOUD) return false; // Iris: no AI features\n"
edit(p, "    public static boolean isAllowed(Profile profile) {\n"
        "        sIneligibilityReason = IneligibilityReason.UNKNOWN;\n",
     "    public static boolean isAllowed(Profile profile) {\n"
     "        sIneligibilityReason = IneligibilityReason.UNKNOWN;\n" + M, M, "Read Aloud off")
add_const(p, "    private static final boolean IRIS_NO_READ_ALOUD = true; // Iris\n", "Read Aloud constant")

# 4) Google Lens
p = "chrome/browser/lens/java/src/org/chromium/chrome/browser/lens/LensController.java"
M = "        if (IRIS_NO_LENS) return false; // Iris: no Google Lens\n"
edit(p, "    public boolean isLensEnabled(LensQueryParams lensQueryParams) {\n"
        "        return mDelegate.isLensEnabled(lensQueryParams);\n",
     "    public boolean isLensEnabled(LensQueryParams lensQueryParams) {\n" + M +
     "        return mDelegate.isLensEnabled(lensQueryParams);\n", M, "Lens off")
add_const(p, "    private static final boolean IRIS_NO_LENS = true; // Iris\n", "Lens constant")
p = "chrome/browser/lens/java/src/org/chromium/chrome/browser/lens/LensSupportStatusHelper.java"
M = "        if (IRIS_NO_LENS) return false; // Iris: no Google Lens\n"
edit(p, "    public static boolean isLensSearchSupported(@Nullable Profile profile, boolean isIncognito) {\n",
     "    public static boolean isLensSearchSupported(@Nullable Profile profile, boolean isIncognito) {\n" + M,
     M, "Lens search off")
add_const(p, "    private static final boolean IRIS_NO_LENS = true; // Iris\n", "Lens search constant")
p = "chrome/browser/flags/android/chrome_feature_list.cc"
new = "BASE_FEATURE(kLensOnQuickActionSearchWidget, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris\n"
s = open(p).read()
if new in s: print("SKIP already applied: %s (Lens widget)" % p)
else:
    import re
    m = re.findall(r"BASE_FEATURE\(kLensOnQuickActionSearchWidget,\s*base::FEATURE_ENABLED_BY_DEFAULT\);\n", s)
    if len(m) != 1: die("%s: kLensOnQuickActionSearchWidget not found exactly once (drift?)" % p)
    open(p, "w").write(s.replace(m[0], new)); print("OK   %s : Lens widget button off" % p)
PY
