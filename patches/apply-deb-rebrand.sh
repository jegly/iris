#!/usr/bin/env bash
# Iris — Linux package identity (jegly 2026-09-26: maintainer jjjegly@gmail.com, project github.com/jegly/iris).
# Verified against checkout 2026-09-26. Chromium's own installer (chrome/installer/linux) builds the .deb; unbranded
# builds read chrome/installer/linux/common/chromium-browser.info (installer.py) and name the output from BUILD.gn's
# `package` — the two MUST match (debian/build.py writes ${info PACKAGE}-${channel}_..., the gn action declares
# ${package}-${channel}_...).
# PACKAGE = iris-browser (not bare "iris": avoids clashing with other packages; not chromium-browser: Ubuntu's own).
# The browser binary must agree with the package, so 3 C++ strings change too (only unbranded #else branches):
#   chrome/common/channel_info_posix.cc      GetDesktopName() "chromium-browser.desktop" -> "iris-browser.desktop"
#       (drives WM_CLASS via shell_integration_linux GetProgramClassClass -> taskbar icon match, default-browser
#        checks; the installer writes StartupWMClass=PACKAGE and ${PACKAGE}.desktop)
#   chrome/browser/shell_integration_linux.cc GetIconName() "chromium-browser" -> "iris-browser" (installer installs the
#       icon as ${PACKAGE}.png, installer.py desktop_icon = PACKAGE)
#   chrome/common/chrome_paths_linux.cc      profile dir ~/.config/chromium -> ~/.config/iris (cache follows:
#       ~/.cache/iris). Keeps Iris from sharing/corrupting a real Chromium profile on the same machine.
# Unchanged on purpose: PROJECT_LICENSE, the Chromium copyright notices, changelog "Build spec" (points at the real
# upstream commit), ENROLLMENTDIR/policy dir (/etc/chromium/policies), flatpak ids (flatpak not built).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new):
    s = open(path).read()
    if new in s and old not in s: print(f"SKIP already applied: {path} ({new[:50]!r})"); return
    if s.count(old) != 1: die(f"{path}: expected 1 match of {old[:60]!r}, found {s.count(old)} (drift?)")
    open(path, "w").write(s.replace(old, new)); print(f"OK   {path} ({new[:60]!r})")

I = "chrome/installer/linux/common/chromium-browser.info"
for old, new in [
    ('PACKAGE="chromium-browser"', 'PACKAGE="iris-browser"'),
    ("INSTALLDIR=/opt/chromium.org/chromium", "INSTALLDIR=/opt/jegly/iris"),
    ('MENUNAME="Chromium Web Browser"', 'MENUNAME="Iris"'),
    ('SHORTDESC="The web browser from the Chromium projects"',
     'SHORTDESC="Iris, a hardened privacy-focused web browser"'),
    ('FULLDESC="Chromium is a browser that combines a minimal design with sophisticated technology to make the web faster, safer, and easier."',
     'FULLDESC="Iris is a hardened, de-Googled web browser based on Chromium, built for privacy and a minimal attack surface."'),
    ('MAINTNAME="Chromium Linux Team"', 'MAINTNAME="jegly"'),
    ('MAINTMAIL="chromium-packagers@chromium.org"', 'MAINTMAIL="jjjegly@gmail.com"'),
    ('PRODUCTURL="https://www.chromium.org/Home"', 'PRODUCTURL="https://github.com/jegly/iris"'),
    ('DEVELOPER_NAME="The Chromium Authors"', 'DEVELOPER_NAME="jegly"'),
    ('BUGTRACKERURL="https://www.chromium.org/for-testers/bug-reporting-guidelines"',
     'BUGTRACKERURL="https://github.com/jegly/iris/issues"'),
    ('HELPURL="https://chromium.googlesource.com/chromium/src/+/main/docs/linux/debugging.md"',
     'HELPURL="https://github.com/jegly/iris"'),
    ('RDN="org.chromium.Chromium"', 'RDN="io.jegly.iris"'),
]:
    edit(I, old, new)

edit("chrome/installer/linux/BUILD.gn",
     '    package = "google-chrome"\n  } else {\n    package = "chromium-browser"\n  }',
     '    package = "google-chrome"\n  } else {\n    package = "iris-browser"  # Iris: must equal PACKAGE in chromium-browser.info\n  }')

edit("chrome/common/channel_info_posix.cc",
     '  return "chromium-browser.desktop";\n#endif',
     '  return "iris-browser.desktop";  // Iris: matches the .deb PACKAGE\n#endif')
edit("chrome/browser/shell_integration_linux.cc",
     '#else  // BUILDFLAG(CHROMIUM_BRANDING)\n  return "chromium-browser";\n#endif',
     '#else  // BUILDFLAG(CHROMIUM_BRANDING)\n  return "iris-browser";  // Iris: matches the .deb PACKAGE\n#endif')
edit("chrome/common/chrome_paths_linux.cc",
     '#else\n  std::string data_dir_basename = "chromium";\n#endif',
     '#else\n  std::string data_dir_basename = "iris";  // Iris: ~/.config/iris\n#endif')
PY
echo "=== Linux package identity (iris-browser) complete ==="
