#!/usr/bin/env bash
# Iris — desktop: GNOME (GTK) colours are used all-or-nothing again (fix for a 157 regression, jegly 2026-11-06:
# "when i click the + to open a new tab the window goes dark dark for a second"; the lock-screen passphrase box was dark
# in a light dialog; both gone with GNOME set to light).
# Verified against 157.0.8103.38: ui/gtk/gtk_color_mixers.cc AddGtkNativeColorMixer() now computes
# palette_matches_color_mode (GTK theme darkness == the browser's light/dark mode). When they disagree (GNOME dark, Iris
# light, or the reverse) 157 keeps GTK's colours for "GTK surfaces" (frame, toolbar, tabs, menus, textfields,
# tooltips) and leaves the rest to the Material/Iris colours -> a dark text box in a light dialog, and a dark toolbar
# colour showing in a new tab before the page paints. 156 applied GTK's set as a whole.
# Iris: when they disagree, skip the GTK colours entirely, so the window follows the mode chosen in Iris
# (Settings -> Appearance -> Mode). When GNOME and Iris agree nothing changes. Desktop only (ui/gtk is not built for
# Android).
# STATUS 2026-11-06: copy-tested on a 157 copy; compile-proven after apply (gtk_color_mixers.o).
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
edit("ui/gtk/gtk_color_mixers.cc",
     "  const bool palette_matches_color_mode =\n"
     "      color_utils::IsDark(primary_bg) ==\n"
     "      (key.color_mode == ui::ColorProviderKey::ColorMode::kDark);\n",
     "  const bool palette_matches_color_mode =\n"
     "      color_utils::IsDark(primary_bg) ==\n"
     "      (key.color_mode == ui::ColorProviderKey::ColorMode::kDark);\n"
     "  // Iris (apply-gtk-mode-match.sh): when GNOME's theme and the mode chosen in\n"
     "  // Iris disagree, use none of the GTK colours (no half-dark, half-light window).\n"
     "  if (!palette_matches_color_mode) {\n"
     "    return;\n"
     "  }\n",
     "// Iris (apply-gtk-mode-match.sh)", "GTK colours all-or-nothing")
PY
echo "=== GTK colours follow the Iris mode complete ==="
