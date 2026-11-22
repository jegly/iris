#!/usr/bin/env bash
# Iris — desktop: GNOME (GTK) colours are used all-or-nothing (fix for a 157 regression, jegly 2026-11-06:
# "when i click the + to open a new tab the window goes dark dark for a second"; the lock-screen passphrase box was dark
# in a light dialog; both gone with GNOME set to light).
# 157: ui/gtk/gtk_color_mixers.cc AddGtkNativeColorMixer() computed palette_matches_color_mode and, on a mismatch
# (GNOME dark + Iris light, or the reverse), kept GTK's colours for "GTK surfaces" only -> half-dark, half-light window.
# 158 (2026-11-20): upstream REMOVED that logic again and applies the GTK set as a whole, like 156, even when GNOME's
# theme and the browser's light/dark mode disagree. Iris keeps its rule on every version: when they disagree, use
# none of the GTK colours, so the window follows the mode chosen in Iris (Settings -> Appearance -> Mode). When GNOME
# and Iris agree nothing changes. Desktop only (ui/gtk is not built for Android).
# STATUS: 157 version copy-tested + compile-proven 2026-11-06; 158 version copy-tested 2026-11-20, NOT compile-proven.
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
p = "ui/gtk/gtk_color_mixers.cc"
s = open(p).read()
IRIS = ("  // Iris (apply-gtk-mode-match.sh): when GNOME's theme and the mode chosen in\n"
        "  // Iris disagree, use none of the GTK colours (no half-dark, half-light window).\n")
if "palette_matches_color_mode" in s:  # 157
    edit(p,
         "  const bool palette_matches_color_mode =\n"
         "      color_utils::IsDark(primary_bg) ==\n"
         "      (key.color_mode == ui::ColorProviderKey::ColorMode::kDark);\n",
         "  const bool palette_matches_color_mode =\n"
         "      color_utils::IsDark(primary_bg) ==\n"
         "      (key.color_mode == ui::ColorProviderKey::ColorMode::kDark);\n" + IRIS +
         "  if (!palette_matches_color_mode) {\n"
         "    return;\n"
         "  }\n",
         "// Iris (apply-gtk-mode-match.sh)", "GTK colours all-or-nothing")
else:  # 158+: decide right after GTK's background colour is read, before any colour is set
    edit(p,
         "  const SkColor primary_bg = GetBgColor(\"\");\n",
         "  const SkColor primary_bg = GetBgColor(\"\");\n" + IRIS +
         "  if (color_utils::IsDark(primary_bg) !=\n"
         "      (key.color_mode == ui::ColorProviderKey::ColorMode::kDark)) {\n"
         "    return;\n"
         "  }\n",
         "// Iris (apply-gtk-mode-match.sh)", "GTK colours all-or-nothing")
PY
echo "=== GTK colours follow the Iris mode complete ==="
