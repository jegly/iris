#!/usr/bin/env bash
# Iris — Security settings page wording (jegly 2026-10-08; verified against 156.0.8078.11):
#  1. "Google Advanced Protection Program" (a link to Google's account-security programme) removed from
#     Settings -> Privacy and security -> Security: both the classic page (row #advancedProtectionProgramLink) and the
#     bundled v2 page (its own card). Hidden with the `hidden` attribute so the TS click handlers stay referenced.
#  2. The Security row on the Privacy page: "Safe Browsing (protection from dangerous sites) and other Iris security
#     settings" (IDS_SETTINGS_SECURITY_DESCRIPTION, text-only change).
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (settings WebUI, grit).
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
S = "chrome/browser/resources/settings/privacy_page/security/"
edit(S + "security_page.html",
     "    <cr-link-row id=\"advancedProtectionProgramLink\" class=\"hr\"\n",
     "    <!-- Iris: no Google Advanced Protection Program link (apply-security-page-iris.sh) -->\n"
     "    <cr-link-row id=\"advancedProtectionProgramLink\" class=\"hr\" hidden\n",
     "id=\"advancedProtectionProgramLink\" class=\"hr\" hidden", "classic page: APP row hidden")
edit(S + "security_page_v2.html",
     "  <settings-section>\n    <cr-link-row id=\"advancedProtectionProgramLinkRow\" class=\"box\"\n",
     "  <!-- Iris: no Google Advanced Protection Program card (apply-security-page-iris.sh) -->\n"
     "  <settings-section hidden>\n    <cr-link-row id=\"advancedProtectionProgramLinkRow\" class=\"box\"\n",
     "<settings-section hidden>\n    <cr-link-row id=\"advancedProtectionProgramLinkRow\"", "v2 page: APP card hidden")
edit("chrome/app/settings_strings.grdp",
     "      Safe Browsing (protection from dangerous sites) and other security settings\n",
     "      Safe Browsing (protection from dangerous sites) and other Iris security settings\n",
     "and other Iris security settings", "Security row description")
PY
echo "=== Security page (Iris) complete ==="
