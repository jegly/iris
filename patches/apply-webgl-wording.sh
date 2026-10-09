#!/usr/bin/env bash
# Iris — clarify the two WebGL switches (jegly 2026-10-09: "keep both, clarify the wording"; the Android Privacy page shows
# both "Allow WebGL" (default site permission) and "Turn WebGL off completely" (hard off) next to each other).
#  - "Turn WebGL off completely": says it overrides "Allow WebGL", even for allowed sites.
#  - "Allow WebGL": says it has no effect while "Turn WebGL off completely" is on.
# Texts only, English-only like the other Iris labels. Needs the toggle patches + apply-iris-hardening-page.sh.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (chrome_java, settings WebUI).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, label):
    s = open(p).read()
    if new in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
OFF_OLD = "No 3D graphics on any website, even ones you allowed. Removes a large attack surface and a way to identify your graphics hardware."
OFF_NEW = ("No 3D graphics on any website. This overrides \"Allow WebGL\", even for sites you allowed. "
           "Removes a large attack surface and a way to identify your graphics hardware.")
edit(J, OFF_OLD, OFF_NEW.replace('"', '\\"'), "Android: off completely")
edit(H, OFF_OLD, OFF_NEW.replace('"', "&quot;"), "desktop: off completely")
edit(J, "3D graphics for websites. Off by default: WebGL exposes details of your graphics hardware that can be used to identify you.",
     "3D graphics for websites. Off by default: WebGL exposes details of your graphics hardware that can be used to identify you."
     " Has no effect while \\\"Turn WebGL off completely\\\" is on.", "Android: allow WebGL")
edit(H, "3D graphics for every website without asking. Off by default: WebGL exposes details of your graphics hardware. &quot;Turn WebGL off completely&quot; overrides this.",
     "3D graphics for every website without asking. Off by default: WebGL exposes details of your graphics hardware."
     " Has no effect while &quot;Turn WebGL off completely&quot; is on.", "desktop: allow WebGL")
PY
echo "=== WebGL wording complete ==="
