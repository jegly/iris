#!/usr/bin/env bash
# Iris — the ⋮ app menu shows no dead entries (jegly 2026-09-27: "Translate and Print greyed out ... should be
# removed if they can't be used"; verified against this checkout).
# chrome/browser/ui/toolbar/app_menu_model.cc added both unconditionally:
#  - Print: shown only when printing is enabled (prefs::kPrintingEnabled; Iris default off,
#    apply-print-discovery-off.sh). Right-click "Print…" already follows that pref upstream.
#  - Translate: removed. Iris does not offer translation, and it would send the page text to Google's service.
# No code looks these items up by index (checked: no GetIndexOfCommandId(IDC_PRINT/IDC_SHOW_TRANSLATE)).
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
p = "chrome/browser/ui/toolbar/app_menu_model.cc"
s = open(p).read()
for inc in ('#include "chrome/common/pref_names.h"', '#include "components/prefs/pref_service.h"'):
    if inc not in s: die(p + ": missing " + inc)
edit(p,
     "  AddItemWithStringIdAndVectorIcon(\n"
     "      this, IDC_PRINT, IDS_PRINT,\n"
     "      features::IsRoundedIconsEnabled() ? kPrintIcon : kPrintMenuOldIcon);\n",
     "  // Iris: no Print entry while printing is disabled (the Iris default).\n"
     "  if (browser_->GetProfile()->GetPrefs()->GetBoolean(prefs::kPrintingEnabled)) {\n"
     "    AddItemWithStringIdAndVectorIcon(\n"
     "        this, IDC_PRINT, IDS_PRINT,\n"
     "        features::IsRoundedIconsEnabled() ? kPrintIcon : kPrintMenuOldIcon);\n"
     "  }\n",
     "Iris: no Print entry", "Print only when printing is enabled")
edit(p,
     "  AddItemWithStringIdAndVectorIcon(this, IDC_SHOW_TRANSLATE, IDS_SHOW_TRANSLATE,\n"
     "                                   vector_icons::kGTranslateIcon);\n",
     "  // Iris: no Translate entry (not offered; would send the page to Google).\n",
     "Iris: no Translate entry", "Translate removed")
PY
echo "=== app menu trim complete ==="
