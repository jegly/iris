#!/usr/bin/env bash
# Iris — Android home screen (New Tab Page): no Google feed, no tip cards, no tip notifications (jegly 2026-10-05,
# from testing the -3 APK: "a spinning circle like it's loading something indefinitely" + "an Iris tip about
# enhance your security"; verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# 1. Feed off entirely: feed::prefs::kEnableSnippets ("ntp_snippets.enable", the switch policies use to remove the
#    Discover feed) default true -> false (components/feed/core/shared_prefs/pref_names.cc). apply-privacy-batch1.sh
#    only collapsed the feed (kArticlesListVisible); a collapsed feed still exists and keeps trying to load from
#    Google, which is the most likely source of the endless spinner (not verified on a device).
# 2. No "ephemeral" tip cards in the home-screen card stack: kSegmentationPlatformEphemeralCardRanker -> disabled
#    (components/segmentation_platform/public/features.cc). These are the promo cards: Enhanced Safe Browsing (the
#    "enhance your security" tip, i.e. Google's Enhanced protection), default browser, save passwords, Lens, address
#    bar position, app bundle, send-tab.
# 3. No "tips" notifications pushing the same promos: kAndroidTipsNotifications -> disabled (same file).
# The other card-stack modules (recent tabs etc., local data) stay.
# STATUS 2026-10-05: copy-tested only, NOT compile-proven (feed prefs, segmentation features); check the home
# screen on the phone after the next APK build.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, label):
    s = open(p).read()
    if new in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

edit("components/feed/core/shared_prefs/pref_names.cc",
     "  registry->RegisterBooleanPref(kEnableSnippets, true);\n",
     "  registry->RegisterBooleanPref(kEnableSnippets, false);  // Iris: no feed\n",
     "feed off (kEnableSnippets)")
F = "components/segmentation_platform/public/features.cc"
edit(F,
     "BASE_FEATURE(kSegmentationPlatformEphemeralCardRanker,\n"
     "#if BUILDFLAG(IS_IOS) || BUILDFLAG(IS_ANDROID)\n"
     "             base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "BASE_FEATURE(kSegmentationPlatformEphemeralCardRanker,\n"
     "#if BUILDFLAG(IS_IOS) || BUILDFLAG(IS_ANDROID)\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no tip cards\n",
     "no ephemeral tip cards")
edit(F,
     "BASE_FEATURE(kAndroidTipsNotifications, base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "BASE_FEATURE(kAndroidTipsNotifications,\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no tip notifications\n",
     "no tips notifications")
PY
echo "=== Android home clean complete ==="
