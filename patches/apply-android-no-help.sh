#!/usr/bin/env bash
# Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
# Iris — Android: no "Help & feedback" in the app menu (jegly 2026-11-07).
# Upstream's item runs ChromeFeedbackCollector (screenshot + device/browser details for a feedback report) and then
# opens support.google.com; a link to the Iris GitHub page instead would let GitHub see who uses Iris (IP address).
# So: the Help item is not added to the app menu (phone menu and the menu with the Help submenu; that one keeps its
# "About Iris" entry), and the Help keyboard shortcut does nothing. Settings > About Iris is unchanged.
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

p = "chrome/android/java/src/org/chromium/chrome/browser/tabbed_mode/TabbedAppMenuPropertiesDelegate.java"
C = ("    /** Iris: no Help item in the app menu (apply-android-no-help.sh). */\n"
     "    private static final boolean IRIS_SHOW_HELP = false;\n\n")
edit(p, "public class TabbedAppMenuPropertiesDelegate extends AppMenuPropertiesDelegateImpl {\n",
     "public class TabbedAppMenuPropertiesDelegate extends AppMenuPropertiesDelegateImpl {\n" + C,
     C, "IRIS_SHOW_HELP constant")
M1 = "        // Help (Iris: not shown, apply-android-no-help.sh)\n"
edit(p, "        // Help\n        modelList.add(buildHelpItem());\n",
     M1 + "        if (IRIS_SHOW_HELP) modelList.add(buildHelpItem());\n", M1, "phone menu: no Help")
M2 = "        // Help submenu (Iris: only its About entry is kept, apply-android-no-help.sh)\n"
edit(p, "        // Help\n        modelList.add(buildHelpParentItem());\n",
     M2 + "        modelList.add(IRIS_SHOW_HELP ? buildHelpParentItem() : buildAboutChromeItem());\n",
     M2, "submenu menu: About only")

p = "chrome/android/java/src/org/chromium/chrome/browser/app/ChromeActivity.java"
M3 = "            // Iris: no Help page, the shortcut does nothing (apply-android-no-help.sh)\n"
edit(p,
     "        if (id == R.id.help_id) {\n"
     "            if (fromMenu) {\n"
     "                String url = currentTab != null ? currentTab.getUrl().getSpec() : \"\";\n"
     "                startHelpAndFeedback(url, \"MobileMenuFeedback\", currentProfile);\n"
     "            } else {\n"
     "                getTabCreator(getTabModelSelector().isIncognitoSelected())\n"
     "                        .launchUrl(\n"
     "                                \"https://support.google.com/chrome?p=help&ctx=keyboard\",\n"
     "                                TabLaunchType.FROM_CHROME_UI);\n"
     "            }\n"
     "            return true;\n"
     "        }\n",
     "        if (id == R.id.help_id) {\n" + M3 + "            return true;\n        }\n",
     M3, "Help shortcut: nothing")
PY
