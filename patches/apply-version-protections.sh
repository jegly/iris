#!/usr/bin/env bash
# Iris — "Iris protections" section on chrome://version (jegly 2026-10-01; both platforms). Verified against this
# checkout. chrome://version's "Command Line" row only shows startup switches, and almost all of Iris's hardening is
# compiled-in defaults, so the page looked like Iris had none. This adds a row that reads the LIVE state from the
# running browser — a protection that is off shows "✗ ... off" — instead of printing fixed names:
#   site isolation + strict origin isolation (SiteIsolationPolicy), JavaScript JIT for websites (JAVASCRIPT_JIT
#   default content setting), encrypted DNS mode + server (local state), HTTPS-Only, third-party cookies (profile
#   prefs), Global Privacy Control, number of risky web APIs off (--disable-blink-features), WebGPU, background
#   networking, Google network time, Gemini, AI Mode, Google Lens (base::Feature state), plus one "Built in" line:
#   component updates limited to CRLSet + certificate data (apply-no-google-startup.sh) and compile-time hardening
#   detected by the compiler itself (CFI buildflag, shadow call stack, PAC+BTI, stack protector, FORTIFY, libc++).
# English-only label (no new grit IDs). New source: patches/src/chrome/browser/ui/webui/version/iris_protections.*
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
PSRC="$(cd "$(dirname "$0")" && pwd)/src"
cd "$SRC"
for f in chrome/browser/ui/webui/version/iris_protections.h chrome/browser/ui/webui/version/iris_protections.cc; do
  [ -f "$PSRC/$f" ] || { echo "ERROR: missing $PSRC/$f" >&2; exit 1; }
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

p = "chrome/browser/ui/webui/version/BUILD.gn"
edit(p, '    "version_handler.cc",\n', '    "iris_protections.cc",  # Iris\n    "iris_protections.h",  # Iris\n'
     '    "version_handler.cc",\n', '"iris_protections.cc",  # Iris', "sources")
edit(p, '    "//chrome/browser:browser_process_impl",\n',
     '    "//chrome/browser:browser_process",  # Iris\n'
     '    "//chrome/browser:browser_process_impl",\n'
     '    "//chrome/browser/content_settings:content_settings_factory",  # Iris\n',
     '"//chrome/browser/content_settings:content_settings_factory",  # Iris', "deps 1")
edit(p, '    "//components/embedder_support:user_agent",\n',
     '    "//components/content_settings/core/browser",  # Iris\n'
     '    "//components/content_settings/core/browser:cookie_settings",  # Iris\n'
     '    "//components/content_settings/core/common",  # Iris\n'
     '    "//components/embedder_support:user_agent",\n'
     '    "//components/lens:features",  # Iris\n'
     '    "//components/network_time",  # Iris\n'
     '    "//components/omnibox/browser:aim_eligibility_service_features",  # Iris\n'
     '    "//components/prefs",  # Iris\n',
     '"//components/lens:features",  # Iris', "deps 2")
edit(p, '    "//content/public/common",\n',
     '    "//content/public/common",\n    "//gpu/config",  # Iris\n'
     '    "//third_party/blink/public/common",  # Iris\n',
     '"//gpu/config",  # Iris', "deps 3")

p = "chrome/browser/ui/webui/version/version_ui.cc"
edit(p, '#include "chrome/browser/ui/webui/version/version_handler.h"\n',
     '#include "chrome/browser/ui/webui/version/iris_protections.h"  // Iris\n'
     '#include "chrome/browser/ui/webui/version/version_handler.h"\n',
     'version/iris_protections.h"  // Iris', "include")
edit(p, "  VersionUI::AddVersionDetailStrings(html_source);\n",
     "  VersionUI::AddVersionDetailStrings(html_source);\n"
     "  html_source->AddString(\"iris_protections\",  // Iris\n"
     "                         iris::ProtectionsReport(profile));\n",
     '"iris_protections",  // Iris', "data string")

p = "components/webui/version/resources/about_version.html"
row = ('        <tr><td class="label">$i18n{command_line_name}</td>\n'
       '          <td class="version" id="command_line">$i18n{command_line}</td>\n'
       '        </tr>\n')
edit(p, row, row +
     '        <tr><td class="label">Iris protections</td>\n'
     '          <td class="version" id="iris_protections">$i18n{iris_protections}</td>\n'
     '        </tr>\n', 'id="iris_protections"', "row")
p = "components/webui/version/resources/about_version.css"
s = open(p).read()
css = "\n/* Iris: one protection per line. */\n#iris_protections {\n  white-space: pre-line;\n}\n"
if "#iris_protections" in s: print("SKIP already applied: %s (css)" % p)
else: open(p, "w").write(s.rstrip("\n") + "\n" + css); print("OK   %s : css" % p)
PY
