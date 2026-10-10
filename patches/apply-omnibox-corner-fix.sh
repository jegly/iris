#!/usr/bin/env bash
# Iris — no specks on the address-bar dropdown's top corners (jegly 2026-10-10: "see the 4 dots?"; verified against
# 156.0.8078.11).
# While the dropdown is open, its top part is a transparent hole the location bar shows through (TopBackgroundView,
# rounded_omnibox_results_frame.cc). Upstream punches the hole at exactly the location bar's size and hides the edge
# with a 1 px non-antialiased band; pixels on the hole's edge stay partly transparent, so the location bar's
# antialiased edge over the toolbar shows through as specks (invisible with similar colours, obvious with contrasting
# Theme editor colours). Measured with a red diagnostic band (jegly's screenshot 2026-10-10 23:06): the specks sit on
# the hole's outermost ring, outside any band drawn inside it.
# Fix: punch the hole 3 px smaller than the location bar (same pill shape). The dropdown's own opaque background then
# covers the location bar's edge completely; the hole's own edge lies over the location bar's opaque inside, so its
# antialiasing is invisible. History: 2 px and 6 px bands inside the hole (did not help; replaced here).
# Needs apply-omnibox-native-popup.sh (otherwise the WebUI dropdown is used and this code is not).
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (rounded_omnibox_results_frame.o). Not seen.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
p = "chrome/browser/ui/views/omnibox/rounded_omnibox_results_frame.cc"
s = open(p).read()
NEW = ("    // Iris: the hole is 3 px smaller than the location bar\n"
       "    // (apply-omnibox-corner-fix.sh): the dropdown's own colour then covers\n"
       "    // the location bar's antialiased edge, which otherwise lets the toolbar\n"
       "    // colour through as specks with contrasting theme colours.\n"
       "    constexpr int kIrisHoleInset = 3;\n"
       "    const int radius =\n"
       "        LocationBarView::ComputeBorderRadius(location_bar_->Bounds().size());\n"
       "    SetBackground(views::CreateBackgroundFromPainter(\n"
       "        views::Painter::CreateSolidRoundRectPainter(\n"
       "            SK_ColorTRANSPARENT,\n"
       "            radius > kIrisHoleInset ? radius - kIrisHoleInset : 0,\n"
       "            gfx::Insets(kIrisHoleInset), SkBlendMode::kSrc,\n"
       "            /*antialias=*/true)));\n")
if NEW in s:
    print("SKIP already applied: %s (hole inset 3 px)" % p); sys.exit(0)
# Upstream block (+ an optional band from earlier Iris versions, any width/colour).
OLD = re.compile(
    r"    const SkColor background_color =\n"
    r"        GetColorProvider\(\)->GetColor\(kColorOmniboxResultsBackground\);\n"
    r"\n"
    r"    // Paint a stroke of the background color as a 1 px border to hide the\n"
    r"    // underlying antialiased location bar/toolbar edge\.  The round rect here is\n"
    r"    // not antialiased, since the goal is to completely cover the underlying\n"
    r"    // pixels, and AA would let those on the edge partly bleed through\.\n"
    r"    SetBackground\(LocationBarView::CreateRoundRectBackground\(\n"
    r"        SK_ColorTRANSPARENT, background_color, location_bar_->Bounds\(\)\.size\(\),\n"
    r"        SkBlendMode::kSrc, false\)\);\n"
    r"(?:    // Iris: a \d+ px band.*?\n        (?:background_color|SK_ColorRED)\)\);[^\n]*\n)?",
    re.S)
m = OLD.search(s)
if not m:
    sys.stderr.write("ERROR: %s: TopBackgroundView::OnThemeChanged body not found (drift?)\n" % p); sys.exit(1)
s = s[:m.start()] + NEW + s[m.end():]
for inc in ('#include "ui/views/background.h"', '#include "ui/views/painter.h"'):
    if inc not in s:
        anchor = '#include "ui/views/bubble/bubble_border.h"\n'
        if s.count(anchor) != 1:
            sys.stderr.write("ERROR: %s: include anchor not found (drift?)\n" % p); sys.exit(1)
        s = s.replace(anchor, inc + "  // Iris\n" + anchor)
open(p, "w").write(s)
print("OK   %s : hole inset 3 px (replaces the 1 px band%s)" % (p, " and the older Iris band" if m.group(0).count("Iris") else ""))
PY
echo "=== omnibox corner fix complete ==="
