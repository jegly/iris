#!/usr/bin/env bash
# Iris — the shield on Android, plus the shared per-site switch logic (0.0.0.7 plan item 2, jegly 2026-10-09 "yes";
# written 2026-10-10; verified against 156.0.8078.11).
#  - chrome/browser/iris/iris_shield_settings.{h,cc} (all platforms, chrome/browser:core): the shield's per-site
#    switches in one place. The desktop panel and the </> button (iris_toolbar_buttons.cc, apply-toolbar-buttons.sh)
#    use it too, so both platforms behave the same; a per-site exception is kept only when it differs from the default
#    (the global Iris hardening switches keep applying).
#  - Android toolbar (phone layout): a shield button at the start of the toolbar's button row (R.id.toolbar_buttons),
#    with the page's blocked count as a badge, tinted like the other toolbar icons. Added at runtime by
#    ToolbarManager.initializeWithNative() (IrisShieldController), so the toolbar module's layouts are untouched.
#    Tablets (other toolbar layout): no button yet.
#  - Tapping it opens IrisShieldSheet: a sheet at the bottom with the desktop panel's content: counts (page, kinds,
#    lifetime), master switch, "This site" switches (ads/trackers, cross-site cookies, JavaScript, JS optimisation,
#    WebGL, Google sign-in prompts, forget site), canvas/audio and browser identity lists, connection details, "Reset
#    this site", and a gear to Privacy and security (Iris hardening). Changes reload the tab.
#  - JNI: IrisShield.java <-> chrome/browser/iris/iris_shield_android.cc (counts + live updates from iris::ShieldStats,
#    which tab_helpers.cc already attaches on Android; switches; connection lines from iris_tls_info).
# English-only labels, like the other Iris Android screens. Needs apply-android-per-site.sh (IrisSiteSettings, JNI
# list anchor), apply-android-themes.sh (resource list anchor), apply-shield-stats.sh, apply-iris-permissions.sh.
# Must run BEFORE apply-toolbar-buttons.sh is built (desktop now includes iris_shield_settings.h).
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (chrome_java, iris_shield_android.o,
#   iris_shield_settings.o, iris_toolbar_buttons.o). UI not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
J=chrome/android/java/src/org/chromium/chrome/browser/iris
for f in chrome/browser/iris/iris_shield_settings.h chrome/browser/iris/iris_shield_settings.cc \
         chrome/browser/iris/iris_shield_android.cc \
         "$J/IrisShield.java" "$J/IrisShieldController.java" "$J/IrisShieldSheet.java" \
         chrome/android/java/res/drawable/iris_ic_shield.xml; do
  from="$DIR/src/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
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

b = "chrome/browser/BUILD.gn"
edit(b, '    "iris/iris_shield_stats.cc",  # Iris\n    "iris/iris_shield_stats.h",  # Iris\n',
     '    "iris/iris_shield_settings.cc",  # Iris (apply-android-shield.sh)\n'
     '    "iris/iris_shield_settings.h",  # Iris (apply-android-shield.sh)\n'
     '    "iris/iris_shield_stats.cc",  # Iris\n    "iris/iris_shield_stats.h",  # Iris\n',
     '"iris/iris_shield_settings.cc"', "shared shield switches")
edit(b, '      "iris/iris_site_settings_android.cc",  # Iris\n',
     '      "iris/iris_shield_android.cc",  # Iris (apply-android-shield.sh)\n'
     '      "iris/iris_site_settings_android.cc",  # Iris\n',
     '"iris/iris_shield_android.cc"', "Android shield JNI source")

js = 'java/src/org/chromium/chrome/browser/iris/IrisSiteSettings.java'
edit("chrome/android/chrome_java_sources.gni", '  "%s",  # Iris\n' % js,
     '  "java/src/org/chromium/chrome/browser/iris/IrisShield.java",  # Iris\n'
     '  "java/src/org/chromium/chrome/browser/iris/IrisShieldController.java",  # Iris\n'
     '  "java/src/org/chromium/chrome/browser/iris/IrisShieldSheet.java",  # Iris\n'
     '  "%s",  # Iris\n' % js,
     'browser/iris/IrisShieldSheet.java"', "Java sources")
edit("chrome/android/BUILD.gn", '      "%s",  # Iris\n' % js,
     '      "java/src/org/chromium/chrome/browser/iris/IrisShield.java",  # Iris\n'
     '      "%s",  # Iris\n' % js,
     '"java/src/org/chromium/chrome/browser/iris/IrisShield.java",  # Iris', "JNI header list")
edit("chrome/android/chrome_java_resources.gni", '  "java/res/values/iris_palettes.xml",  # Iris\n',
     '  "java/res/drawable/iris_ic_shield.xml",  # Iris (apply-android-shield.sh)\n'
     '  "java/res/values/iris_palettes.xml",  # Iris\n',
     '"java/res/drawable/iris_ic_shield.xml"', "shield icon resource")

t = "chrome/android/java/src/org/chromium/chrome/browser/toolbar/ToolbarManager.java"
edit(t, "    private boolean mInitializedWithNative;\n",
     "    private boolean mInitializedWithNative;\n"
     "    // Iris: shield button in the toolbar (apply-android-shield.sh).\n"
     "    private org.chromium.chrome.browser.iris.@Nullable IrisShieldController mIrisShield;\n",
     "IrisShieldController mIrisShield;", "shield field")
edit(t, "        mInitializedWithNative = true;\n",
     "        mInitializedWithNative = true;\n"
     "        // Iris: shield button in the toolbar (apply-android-shield.sh).\n"
     "        mIrisShield =\n"
     "                org.chromium.chrome.browser.iris.IrisShieldController.attach(\n"
     "                        mActivity,\n"
     "                        mControlContainer.getView(),\n"
     "                        mActivityTabProvider,\n"
     "                        mToolbarThemeColorProvider);\n",
     "IrisShieldController.attach(", "shield attach")
edit(t, "        if (mIsDestroyed) return;\n        mIsDestroyed = true;\n",
     "        if (mIsDestroyed) return;\n        mIsDestroyed = true;\n"
     "        if (mIrisShield != null) {\n"
     "            mIrisShield.destroy();  // Iris (apply-android-shield.sh)\n"
     "            mIrisShield = null;\n"
     "        }\n",
     "mIrisShield.destroy();", "shield destroy")
PY
echo "=== Android shield + shared shield switches complete ==="
