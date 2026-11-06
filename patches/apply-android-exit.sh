#!/usr/bin/env bash
# Iris — Android: "Exit" in the app menu; clear-on-exit really clears on exit (issue #1 item 5, jegly 2026-11-05).
# Before: "Clear browsing data when Iris starts" (apply-privacy-toggles-2.sh) only cleared at the NEXT start, because
# Android has no "last window closed": the data stayed on disk while Iris sat in the background or was killed.
# Now: app menu > Exit (after Help) -> IrisExit.java -> native iris_exit_android.cc: if IrisShredder filled the
# clear-on-exit list, ChromeBrowsingDataLifetimeManager::ClearBrowsingDataForOnExitPolicy(keep_browser_alive=true)
# removes it now; Iris waits until it clears kClearBrowsingDataOnExitDeletionPending (at most 10 s; if the time runs
# out the flag stays set and the next start finishes the job), then ApplicationLifetime.terminate(false) = every
# activity finishes and BrowserRestartActivity kills the process (no relaunch). Same approach as UC-Android's exit.
# Without clear-on-exit, Exit just quits. Verified against 157.0.8103.38.
# New (patches/src): chrome/android/java/.../iris/IrisExit.java, chrome/browser/iris/iris_exit_android.cc,
#   chrome/android/java/res/drawable/iris_exit_24dp.xml (Tabler "power", MIT; Android notices: TODO, see 00_STATE).
# Wiring: chrome_java_sources.gni, chrome_jni_headers, chrome/browser/BUILD.gn (next to iris_app_lock_android.cc),
#   chrome_java_resources.gni, ids.xml (R.id.iris_exit_menu_id), TabbedAppMenuPropertiesDelegate (item),
#   ChromeActivity.onMenuOrKeyboardAction (handler). English-only "Exit" (no grit rebuild).
# Needs apply-android-app-lock (anchors). STATUS 2026-11-05: copy-tested on 157 copies, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
PSRC="$(cd "$(dirname "$0")" && pwd)/src"
cd "$SRC"
for f in chrome/android/java/src/org/chromium/chrome/browser/iris/IrisExit.java \
         chrome/browser/iris/iris_exit_android.cc \
         chrome/android/java/res/drawable/iris_exit_24dp.xml; do
  [ -f "$PSRC/$f" ] || { echo "ERROR: missing $PSRC/$f" >&2; exit 1; }
  mkdir -p "$(dirname "$f")"
  if cmp -s "$PSRC/$f" "$f"; then echo "SKIP already applied: $f"; else cp "$PSRC/$f" "$f"; echo "OK   $f : copied"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
J = "java/src/org/chromium/chrome/browser/iris/"
a = '  "%sIrisAppLock.java",  # Iris\n' % J
edit("chrome/android/chrome_java_sources.gni", a, a + '  "%sIrisExit.java",  # Iris\n' % J,
     '"%sIrisExit.java",  # Iris' % J, "java source")
a = '      "%sIrisAppLock.java",  # Iris\n' % J
edit("chrome/android/BUILD.gn", a, a + '      "%sIrisExit.java",  # Iris\n' % J,
     '      "%sIrisExit.java",  # Iris' % J, "JNI header")
a = '      "iris/iris_app_lock_android.cc",  # Iris\n'
edit("chrome/browser/BUILD.gn", a, a + '      "iris/iris_exit_android.cc",  # Iris\n',
     '"iris/iris_exit_android.cc",  # Iris', "JNI source")
a = '  "java/res/drawable/ic_fullscreen_exit.xml",\n'
edit("chrome/android/chrome_java_resources.gni", a, a + '  "java/res/drawable/iris_exit_24dp.xml",  # Iris\n',
     '"java/res/drawable/iris_exit_24dp.xml"', "icon resource")
a = '    <item type="id" name="preferences_id" />\n'
edit("chrome/android/java/res/values/ids.xml", a, a + '    <item type="id" name="iris_exit_menu_id" /> <!-- Iris -->\n',
     'name="iris_exit_menu_id"', "menu id")
edit("chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java",
     "        // Help\n        modelList.add(buildHelpItem());\n",
     "        // Help\n        modelList.add(buildHelpItem());\n\n"
     "        // Iris: Exit - clears data if \"clear on exit\" is on, then quits (apply-android-exit.sh).\n"
     "        PropertyModel irisExitModel =\n"
     "                AppMenuItemUtils.buildModelForStandardMenuItem(\n"
     "                        mContext,\n"
     "                        getAppMenuItemTheme(),\n"
     "                        R.id.iris_exit_menu_id,\n"
     "                        R.string.menu_settings, // replaced below (English-only label)\n"
     "                        shouldShowIconBeforeItem() ? R.drawable.iris_exit_24dp : Resources.ID_NULL,\n"
     "                        isMenuIconAtStart());\n"
     "        irisExitModel.set(AppMenuItemProperties.TITLE, \"Exit\");\n"
     "        modelList.add(new ListItem(AppMenuHandler.AppMenuItemType.STANDARD, irisExitModel));\n",
     "R.id.iris_exit_menu_id", "menu item")
edit("chrome/android/java/src/org/chromium/chrome/browser/app/ChromeActivity.java",
     "        if (id == R.id.preferences_id) {\n",
     "        if (id == R.id.iris_exit_menu_id) { // Iris (apply-android-exit.sh)\n"
     "            org.chromium.chrome.browser.iris.IrisExit.exit();\n"
     "            return true;\n"
     "        }\n\n"
     "        if (id == R.id.preferences_id) {\n",
     "R.id.iris_exit_menu_id", "menu handler")
PY
echo "=== Android Exit complete ==="
