#!/usr/bin/env bash
# Iris — block cross-site parser-blocking scripts that a page inserts with document.write() in the main frame
# (jegly 2026-09-30; = chrome://flags #disallow-doc-written-script-loads, which upstream only applies on 2G).
# Compiled in next to the other Iris switches (apply-default-switches.sh block in chrome/app/chrome_main_delegate.cc),
# so it also holds on Android. Merged into any existing --blink-settings value (read as a single switch), like the
# GPC --enable-features merge. Renderers get --blink-settings from the browser (render_process_host_impl.cc list).
# Guarded; idempotent; fails loudly on drift. Needs apply-default-switches + apply-gpc-on first.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
grep -q 'blink::switches::kBlinkSettings,' content/browser/renderer_host/render_process_host_impl.cc \
  || { echo "ERROR: --blink-settings no longer propagated to renderers" >&2; exit 1; }
grep -q '"disallowFetchForDocWrittenScriptsInMainFrame=true"' chrome/browser/about_flags.cc \
  || { echo "ERROR: blink setting name changed (about_flags.cc)" >&2; exit 1; }
python3 - <<'PY'
import sys
p = "chrome/app/chrome_main_delegate.cc"
s = open(p).read()
marker = "disallowFetchForDocWrittenScriptsInMainFrame=true"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
anchor = ("#if !BUILDFLAG(IS_ANDROID)\n"
          "    // Desktop first-run (welcome/import prompts) off; Android handled in FirstRunStatus.java.\n")
if s.count(anchor) != 1 or "Iris: compiled-in hardening switches" not in s:
    sys.stderr.write("ERROR: %s: anchor not found exactly once (run apply-default-switches first / drift?)\n" % p); sys.exit(1)
block = ('''    // Iris: no cross-site parser-blocking scripts via document.write() in the
    // main frame (apply-docwrite-block.sh). Merged into any --blink-settings.
    {
      std::string iris_blink_settings =
          iris_command_line->GetSwitchValueASCII("blink-settings");
      if (!iris_blink_settings.empty()) {
        iris_blink_settings += ",";
      }
      iris_blink_settings += "disallowFetchForDocWrittenScriptsInMainFrame=true";
      iris_command_line->AppendSwitchASCII("blink-settings", iris_blink_settings);
    }
''')
open(p, "w").write(s.replace(anchor, block + anchor, 1)); print("OK   " + p + " : document.write script block")
PY
echo "=== document.write block complete ==="
