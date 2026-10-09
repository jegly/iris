#!/usr/bin/env bash
# Iris — extra toolbar buttons (jegly 2026-10-09: "build it all"; shield with a blocked count like Brave's, a JavaScript
# button, "New identity" (the one Tor idea he wanted) and a lock button; verified against 156.0.8078.11).
# New code (patches/src): chrome/browser/ui/views/toolbar/iris_toolbar_buttons.{h,cc} — one container view with four
# ToolbarButtons plus the shield panel (a bubble). Added in ToolbarView::Init() right before the overflow / menu
# buttons. Desktop only.
#   Shield        icon + the page's blocked total (ads/trackers + blocked cookies + protected fingerprint reads, from
#                 iris::ShieldStats, apply-shield-stats.sh). Panel: counts, "Block ads and trackers on this site" (the
#                 per-site ADS setting), canvas/audio reading preset for the site, link to Iris hardening.
#   JavaScript    per-site JAVASCRIPT content setting; shows "off" in red when blocked; reloads the tab.
#   New identity  click twice (armed for 4 s): BrowsingDataRemover wipes site data, cache, history and downloads (all time),
#                 new random canvas/audio seed (RerollFingerprintSeed), a new tab opens and the other tabs in this window
#                 close. Other windows are left alone.
#   Lock          only when the app lock is on: quits Iris (it asks for the passphrase on the next start).
# Each button has a switch in Settings -> Appearance (prefs iris.ui.toolbar_{shield,javascript,new_identity,lock}, all
# default ON, registered in iris_shredder.cc).
# Needs apply-toolbar-icons (kIris*Icon), apply-shield-stats, apply-fingerprint, apply-traffic-lights (Appearance anchor
# is the same toolbarRow). STATUS 2026-10-09: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for to in chrome/browser/ui/views/toolbar/iris_toolbar_buttons.h chrome/browser/ui/views/toolbar/iris_toolbar_buttons.cc \
          chrome/browser/iris/iris_fingerprint_host.h chrome/browser/iris/iris_fingerprint_host.cc; do
  from="$DIR/src/$to"; [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
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
T = "chrome/browser/ui/views/toolbar/"
edit(T + "BUILD.gn", "    \"home_button.h\",\n",
     "    \"home_button.h\",\n    \"iris_toolbar_buttons.h\",  # Iris\n",
     "iris_toolbar_buttons.h", "BUILD: header")
edit(T + "BUILD.gn", "    \"home_button.cc\",\n",
     "    \"home_button.cc\",\n    \"iris_toolbar_buttons.cc\",  # Iris\n",
     "iris_toolbar_buttons.cc", "BUILD: source")
edit(T + "toolbar_view.cc", "#include \"chrome/browser/ui/views/toolbar/home_button.h\"\n",
     "#include \"chrome/browser/ui/views/toolbar/home_button.h\"\n"
     "#include \"chrome/browser/ui/views/toolbar/iris_toolbar_buttons.h\"  // Iris\n",
     "iris_toolbar_buttons.h\"  // Iris", "include")
edit(T + "toolbar_view.cc",
     "  // Only manage the overflow button when there are at least some views\n",
     "  // Iris: shield / JavaScript / new identity / lock buttons (apply-toolbar-buttons.sh).\n"
     "  AddChildView(std::make_unique<IrisToolbarButtons>(browser_));\n\n"
     "  // Only manage the overflow button when there are at least some views\n",
     "std::make_unique<IrisToolbarButtons>(browser_)", "add buttons")
P = ("shield", "javascript", "new_identity", "lock")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-toolbar-buttons.sh\n"
     + "".join("  (*s_allowlist)[\"iris.ui.toolbar_%s\"] = settings_api::PrefType::kBoolean;\n" % k for k in P)
     + "  // Iris: apply-privacy-toggles-3.sh\n",
     "\"iris.ui.toolbar_shield\"", "allowlist")
A = "chrome/browser/resources/settings/appearance_page/appearance_page.html.ts"
rows = [("shield", "Shield button",
         "Shows how many ads, trackers and cookies were blocked on the page. Click it for this site's settings."),
        ("javascript", "JavaScript button",
         "Turns JavaScript on or off for the site you are on."),
        ("new_identity", "New identity button",
         "Erases site data, cache, history and downloads, closes the other tabs and starts fresh. Click twice to confirm."),
        ("lock", "Lock button",
         "Locks and closes Iris. Only shown while the app lock is on.")]
html = "    <!-- Iris: toolbar buttons (apply-toolbar-buttons.sh; English-only) -->\n" + "".join(
    "    <settings-toggle-button id=\"irisToolbar%sToggle\" class=\"hr\"\n"
    "        pref-key=\"iris.ui.toolbar_%s\"\n"
    "        label=\"%s\"\n"
    "        sub-label=\"%s\">\n"
    "    </settings-toggle-button>\n" % (k.title().replace("_", ""), k, t, d) for k, t, d in rows)
edit(A, "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     html + "    <div id=\"toolbarRow\" class=\"settings-row\">\n",
     "irisToolbarShieldToggle", "Appearance toggles")
# Lock button mode (jegly 2026-10-09): "Lock without closing Iris" hides the windows until the passphrase is entered
# (IrisScreenLock in iris_toolbar_buttons.cc, Linux) instead of quitting. Pref iris.ui.lock_keep_open, default off.
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.ui.toolbar_lock\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.ui.toolbar_lock\"] = settings_api::PrefType::kBoolean;\n"
     "  (*s_allowlist)[\"iris.ui.lock_keep_open\"] = settings_api::PrefType::kBoolean;\n",
     "\"iris.ui.lock_keep_open\"", "allowlist: lock mode")
edit(A, "        sub-label=\"Locks and closes Iris. Only shown while the app lock is on.\">\n"
        "    </settings-toggle-button>\n",
     "        sub-label=\"Locks Iris. Only shown while the app lock is on.\">\n"
     "    </settings-toggle-button>\n"
     "    <settings-toggle-button id=\"irisLockKeepOpenToggle\" class=\"hr\"\n"
     "        pref-key=\"iris.ui.lock_keep_open\"\n"
     "        label=\"Lock without closing Iris\"\n"
     "        sub-label=\"The lock button hides all Iris windows until you enter your passphrase, instead of closing Iris. "
     "Faster to come back to, but your data stays unlocked in memory while Iris runs; closing Iris is the stronger lock.\">\n"
     "    </settings-toggle-button>\n",
     "irisLockKeepOpenToggle", "Appearance: lock mode")
PY
echo "=== toolbar buttons complete ==="
