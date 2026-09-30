#!/usr/bin/env bash
# Iris — navigator.platform / navigator.vendor / navigator.productSub follow the per-site browser identity
# (jegly 2026-09-30: with "Safari on macOS" browserleaks still showed platform "Linux x86_64" + vendor "Google Inc.").
# Derived from the user agent the page already gets (ExecutionContext::UserAgent(), i.e. the Iris override):
#   "Windows NT" -> platform Win32 | "Macintosh" -> platform MacIntel (window + workers, NavigatorBase::platform)
#   "Firefox/" -> vendor "" + productSub "20100101" | Safari (Safari/ + Version/, no Chrome/) -> "Apple Computer, Inc."
# The default Iris UA ("X11; Linux x86_64 ... Chrome/") and Android UAs match none of these: unchanged.
# DevTools' platform override (Settings) still wins in Navigator::platform(). NOT covered (would need IDL = long
# rebuild): Firefox-only navigator.oscpu / buildID, window.chrome, CSS/JS engine differences, TLS fingerprint.
# Two Blink .cc files, no header/IDL/json5 change. Guarded; idempotent; fails loudly on drift.
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

edit("third_party/blink/renderer/core/execution_context/navigator_base.cc",
     "String NavigatorBase::platform() const {\n",
     "String NavigatorBase::platform() const {\n"
     "  // Iris: follow a per-site browser identity (apply-ua-navigator-consistency.sh).\n"
     "  const String iris_user_agent = userAgent();\n"
     "  if (iris_user_agent.contains(\"Windows NT\")) {\n"
     "    return \"Win32\";\n"
     "  }\n"
     "  if (iris_user_agent.contains(\"Macintosh\")) {\n"
     "    return \"MacIntel\";\n"
     "  }\n",
     "apply-ua-navigator-consistency.sh", "platform")

p = "third_party/blink/renderer/core/frame/navigator.cc"
edit(p,
     'String Navigator::productSub() const {\n  return "20030107";\n}\n',
     'String Navigator::productSub() const {\n'
     '  // Iris: Firefox reports 20100101 (apply-ua-navigator-consistency.sh).\n'
     '  if (userAgent().contains("Firefox/")) {\n'
     '    return "20100101";\n'
     '  }\n'
     '  return "20030107";\n'
     '}\n',
     'Firefox reports 20100101', "productSub")
edit(p,
     '  return "Google Inc.";\n}\n',
     '  // Iris: follow a per-site browser identity (apply-ua-navigator-consistency.sh).\n'
     '  const String iris_user_agent = userAgent();\n'
     '  if (iris_user_agent.contains("Firefox/")) {\n'
     '    return "";\n'
     '  }\n'
     '  if (iris_user_agent.contains("Safari/") &&\n'
     '      iris_user_agent.contains("Version/") &&\n'
     '      !iris_user_agent.contains("Chrome/")) {\n'
     '    return "Apple Computer, Inc.";\n'
     '  }\n'
     '  return "Google Inc.";\n}\n',
     '"Apple Computer, Inc."', "vendor")
PY
echo "=== navigator platform/vendor follow the identity ==="
