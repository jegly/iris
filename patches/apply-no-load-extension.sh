#!/usr/bin/env bash
# Iris — ignore --load-extension (jegly 2026-10-03; verified against the 156.0.8073.0 sources).
# Before: any program could start Iris with --load-extension=<dir> and run its own extension in the user's profile
# (infostealers use this to read cookies/pages). Google Chrome ignores the switch since M137, but
# chrome/browser/extensions/extension_service.cc only does so `#if BUILDFLAG(GOOGLE_CHROME_BRANDING)`.
# After: Iris ignores it like Google Chrome (desktop; ChromeOS branch untouched, Android has no extensions).
# Unpacked extensions still load the normal way: chrome://extensions -> Developer mode -> "Load unpacked".
# Web Store installs are unaffected. --disable-extensions-except is left to upstream (its own feature flag).
# Not changed: --load-and-launch-app (loads Chrome Apps only: UnpackedInstaller only_allow_apps = true).
# Two guards change together, else ShouldBlockCommandLineExtension() becomes an unused function (build error).
# STATUS 2026-10-03: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/extensions/extension_service.cc"
s = open(p).read()
MARK = "// Iris: --load-extension ignored like in Google Chrome"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
o1 = ("#if !BUILDFLAG(GOOGLE_CHROME_BRANDING) || BUILDFLAG(IS_CHROMEOS)\n"
      "const char kBlockLoadCommandline[] = \"command_line\";\n")
n1 = ("// Iris: --load-extension ignored like in Google Chrome (only ChromeOS uses this).\n"
      "#if BUILDFLAG(IS_CHROMEOS)\n"
      "const char kBlockLoadCommandline[] = \"command_line\";\n")
o2 = ("  if (switch_name == switches::kLoadExtension) {\n"
      "#if BUILDFLAG(GOOGLE_CHROME_BRANDING) && !BUILDFLAG(IS_CHROMEOS)\n"
      "    LOG(WARNING)\n"
      "        << \"--load-extension is not allowed in Google Chrome, ignoring.\";\n"
      "    return;\n"
      "#else   // BUILDFLAG(GOOGLE_CHROME_BRANDING) && !BUILDFLAG(IS_CHROMEOS)\n")
n2 = ("  if (switch_name == switches::kLoadExtension) {\n"
      "#if !BUILDFLAG(IS_CHROMEOS)  // Iris: was GOOGLE_CHROME_BRANDING && !IS_CHROMEOS\n"
      "    LOG(WARNING) << \"--load-extension is not allowed in Iris, ignoring.\";\n"
      "    return;\n"
      "#else   // !BUILDFLAG(IS_CHROMEOS)\n")
o3 = "#endif  // BUILDFLAG(GOOGLE_CHROME_BRANDING) && !BUILDFLAG(IS_CHROMEOS)\n  } else if"
n3 = "#endif  // !BUILDFLAG(IS_CHROMEOS)\n  } else if"
for o, what in ((o1, "ShouldBlockCommandLineExtension guard"), (o2, "--load-extension branding guard"),
                (o3, "#endif of the branding guard")):
    if s.count(o) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
s = s.replace(o1, n1, 1).replace(o2, n2, 1).replace(o3, n3, 1)
if "ShouldBlockCommandLineExtension(*profile_)" not in s.split(n2, 1)[1].split(n3, 1)[0]:
    die("%s: ShouldBlockCommandLineExtension no longer inside the #else branch" % p)
open(p, "w").write(s)
print("OK   %s : --load-extension ignored" % p)
PY
echo "=== --load-extension removal complete ==="
