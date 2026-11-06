#!/usr/bin/env bash
# Iris — component updater sends no event pings (issue #1 item 3, jegly 2026-11-05).
# Verified against 157.0.8103.38 (gitiles copies, 2026-11-05): update_client sends its event reports (install/update
# results) to Configurator::PingUrl(). components/component_updater/configurator_impl.cc returns UpdateUrl() there
# while pings_enabled_ is true, which it is unless the command line has --component-updater=disable-pings.
# Iris sets pings_enabled_ = false in the constructor instead of compiling in the switch: base::CommandLine keeps ONE value per switch,
# so an appended --component-updater=disable-pings would replace a user's own --component-updater=... (or be replaced
# by it). The update checks themselves (UpdateUrl) are untouched, so CRLSet + PKI metadata keep updating
# (allowlist: apply-no-google-startup.sh). Bromite's patch also blanks the update URLs - not copied.
# STATUS 2026-11-05: copy-tested on a 157 file copy, NOT compile-proven.
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

# pings_enabled_ stays the gate PingUrl() reads (removing that read would leave an unused private field =
# -Wunused-private-field error); it is just never taken from the command line.
edit("components/component_updater/configurator_impl.cc",
     "      pings_enabled_(config_policy.PingsEnabled()),\n",
     "      // Iris (apply-updater-pings-off): no install/update event reports to\n"
     "      // Google; update checks (CRLSet, PKI metadata) are unaffected.\n"
     "      pings_enabled_(false),\n",
     "// Iris (apply-updater-pings-off)", "pings off")
PY
echo "=== component updater pings off complete ==="
