#!/usr/bin/env bash
# Iris — no specks on the address-bar dropdown's top corners (jegly 2026-10-10: "see the 4 dots?"; verified against
# 156.0.8078.11). While the dropdown is open, its top part is a transparent hole the real address bar shows through
# (TopBackgroundView, rounded_omnibox_results_frame.cc), hidden at the edge by a 1 px band of the dropdown colour.
# On the curved corners that band does not cover the address bar's antialiased edge pixels, so the toolbar colour
# shows through as a few specks; invisible with similar colours, obvious with contrasting Theme editor colours.
# Fix: a wider rounded band of the dropdown colour (same radius as the address bar) on top of the original. Same
# colour as the address bar behind it, so the band itself is invisible.
# History: 2 px (first try) left the specks a few px in on the corner curve -> 6 px (jegly 2026-10-10 "still 4
# pixels"). Trees with an older width are upgraded in place.
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (rounded_omnibox_results_frame.o). Not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
WIDTH = 6
p = "chrome/browser/ui/views/omnibox/rounded_omnibox_results_frame.cc"
s = open(p).read()
anchor = ("    SetBackground(LocationBarView::CreateRoundRectBackground(\n"
          "        SK_ColorTRANSPARENT, background_color, location_bar_->Bounds().size(),\n"
          "        SkBlendMode::kSrc, false));\n")
band = ("    // Iris: a %d px band, not 1 px, so the location bar's antialiased\n"
        "    // corners cannot let the toolbar colour through with contrasting\n"
        "    // theme colours (apply-omnibox-corner-fix.sh).\n"
        "    SetBorder(views::CreateRoundedRectBorder(\n"
        "        %d,\n"
        "        LocationBarView::ComputeBorderRadius(location_bar_->Bounds().size()),\n"
        "        background_color));\n") % (WIDTH, WIDTH)
old_band = re.compile(r"    // Iris: a \d+ px band, not 1 px.*?\n        background_color\)\);\n", re.S)
m = old_band.search(s)
if m and m.group(0) == band:
    print("SKIP already applied: %s (%d px corner band)" % (p, WIDTH))
elif m:
    s = s[:m.start()] + band + s[m.end():]
    open(p, "w").write(s); print("OK   %s : corner band upgraded to %d px" % (p, WIDTH))
elif s.count(anchor) == 1:
    s = s.replace(anchor, anchor + band)
    if '#include "ui/views/border.h"' not in s:
        inc = '#include "ui/views/bubble/bubble_border.h"\n'
        if s.count(inc) != 1:
            sys.stderr.write("ERROR: %s: include anchor not found (drift?)\n" % p); sys.exit(1)
        s = s.replace(inc, '#include "ui/views/border.h"  // Iris\n' + inc)
    open(p, "w").write(s); print("OK   %s : %d px corner band" % (p, WIDTH))
else:
    sys.stderr.write("ERROR: %s: TopBackgroundView background not found (drift?)\n" % p); sys.exit(1)
PY
echo "=== omnibox corner fix complete ==="
