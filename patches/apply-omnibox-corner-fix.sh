#!/usr/bin/env bash
# Iris — no specks on the address-bar dropdown's top corners (jegly 2026-10-10: "see the 4 dots?"; verified against
# 156.0.8078.11). While the dropdown is open, its top part is a transparent hole the real address bar shows through
# (TopBackgroundView, rounded_omnibox_results_frame.cc), hidden at the edge by a 1 px band of the dropdown colour.
# On the curved corners 1 px does not cover the address bar's antialiased edge pixels, so the toolbar colour shows
# through as a few specks; invisible with similar colours, obvious with contrasting Theme editor colours. Fix: a 2 px
# rounded band of the dropdown colour (same radius as the address bar) on top of the original.
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (rounded_omnibox_results_frame.o). Not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/ui/views/omnibox/rounded_omnibox_results_frame.cc"
s = open(p).read()
old = ("    SetBackground(LocationBarView::CreateRoundRectBackground(\n"
       "        SK_ColorTRANSPARENT, background_color, location_bar_->Bounds().size(),\n"
       "        SkBlendMode::kSrc, false));\n")
new = old + ("    // Iris: a 2 px band, not 1 px, so the location bar's antialiased\n"
             "    // corners cannot let the toolbar colour through with contrasting\n"
             "    // theme colours (apply-omnibox-corner-fix.sh).\n"
             "    SetBorder(views::CreateRoundedRectBorder(\n"
             "        2,\n"
             "        LocationBarView::ComputeBorderRadius(location_bar_->Bounds().size()),\n"
             "        background_color));\n")
if "apply-omnibox-corner-fix.sh" in s:
    print("SKIP already applied: " + p)
elif s.count(old) == 1:
    s = s.replace(old, new)
    if '#include "ui/views/border.h"' not in s:
        inc = '#include "ui/views/bubble/bubble_border.h"\n'
        if s.count(inc) != 1:
            sys.stderr.write("ERROR: %s: include anchor not found (drift?)\n" % p); sys.exit(1)
        s = s.replace(inc, '#include "ui/views/border.h"  // Iris\n' + inc)
    open(p, "w").write(s); print("OK   " + p + " : 2 px corner band")
else:
    sys.stderr.write("ERROR: %s: TopBackgroundView background not found (drift?)\n" % p); sys.exit(1)
PY
echo "=== omnibox corner fix complete ==="
