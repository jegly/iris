#!/usr/bin/env bash
# Iris — shield counter, part 2: the per-tab ShieldStats helper (jegly 2026-10-09). Reads the numbers exposed by
# apply-shield-sources.sh and counts protected fingerprint reads. New code: chrome/browser/iris/iris_shield_stats.{h,cc}
# (patches/src). Attached to every tab in TabHelpers::AttachTabHelpers; IrisFingerprintHost reports the first protected
# canvas/audio read of each document through ShieldStats::NoteFingerprintProtected().
# Desktop only (the toolbar shield is desktop; Android has no equivalent surface). The helper itself builds on Android too
# but is only attached by tab_helpers.cc (desktop + Android both include it), so the host call is guarded by a null check.
# Needs apply-shield-sources.sh, apply-fingerprint.sh, apply-page-info-tls.sh (anchors). STATUS 2026-10-09: copy-tested
# only, NOT compile-proven (iris_shield_stats.o, tab_helpers.o, iris_fingerprint_host.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in iris_shield_stats.h iris_shield_stats.cc; do
  to="chrome/browser/iris/$f"; from="$DIR/src/$to"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
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
edit("chrome/browser/BUILD.gn", "    \"iris/iris_tls_info.cc\",  # Iris\n",
     "    \"iris/iris_shield_stats.cc\",  # Iris\n    \"iris/iris_shield_stats.h\",  # Iris\n"
     "    \"iris/iris_tls_info.cc\",  # Iris\n",
     "iris/iris_shield_stats.cc", "BUILD: sources")
t = "chrome/browser/ui/tab_helpers.cc"
edit(t, "#include \"chrome/browser/iris/iris_tls_info.h\"  // nogncheck  Iris (TLS details)\n",
     "#include \"chrome/browser/iris/iris_shield_stats.h\"  // nogncheck  Iris (shield counter)\n"
     "#include \"chrome/browser/iris/iris_tls_info.h\"  // nogncheck  Iris (TLS details)\n",
     "iris_shield_stats.h", "include")
edit(t, "  iris::TlsInfoTabHelper::CreateForWebContents(web_contents);  // Iris (TLS details)\n",
     "  iris::TlsInfoTabHelper::CreateForWebContents(web_contents);  // Iris (TLS details)\n"
     "  iris::ShieldStats::CreateForWebContents(web_contents);  // Iris (shield counter)\n",
     "iris::ShieldStats::CreateForWebContents", "tab helper attached")
h = "chrome/browser/iris/iris_fingerprint_host.cc"
edit(h, '#include "chrome/browser/content_settings/host_content_settings_map_factory.h"\n',
     '#include "chrome/browser/content_settings/host_content_settings_map_factory.h"\n'
     '#include "chrome/browser/iris/iris_shield_stats.h"\n',
     "iris_shield_stats.h", "host include")
edit(h, "    std::move(callback).Run(mode, SeedFor(context, top));\n  }\n",
     "    // Counted by the toolbar shield (apply-shield-stats.sh).\n"
     "    ShieldStats::NoteFingerprintProtected(&rfh);\n"
     "    std::move(callback).Run(mode, SeedFor(context, top));\n  }\n",
     "ShieldStats::NoteFingerprintProtected(&rfh)", "host reports reads")
PY
echo "=== shield stats complete ==="
