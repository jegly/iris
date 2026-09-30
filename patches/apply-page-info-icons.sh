#!/usr/bin/env bash
# Iris — Page Info icons for the Iris permission rows (2026-09-28). PageInfoViewFactory::GetPermissionIcon() hits
# NOTREACHED() (browser crash on opening Page Info) for any ContentSettingsType without an icon case. Page Info
# shows IRIS_WEBGL and IRIS_GOOGLE_SIGNIN (apply-iris-permissions.sh), so give both an icon, with the "off" icon when
# blocked like the upstream rows: WebGL = videogame_asset, Google sign-in = account_circle.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/ui/views/page_info/page_info_view_factory.cc"
s = open(p).read()
if "ContentSettingsType::IRIS_WEBGL" in s:
    print("SKIP already applied: " + p)
else:
    old = ('    default:\n'
           '      // All other |ContentSettingsType|s do not have icons on desktop or are\n'
           '      // not shown in the Page Info bubble.\n'
           '      NOTREACHED();\n')
    new = ('    // Iris permission rows (apply-page-info-icons.sh).\n'
           '    case ContentSettingsType::IRIS_WEBGL:\n'
           '      icon = show_blocked_badge ? &vector_icons::kVideogameAssetOffIcon\n'
           '                                : &vector_icons::kVideogameAssetIcon;\n'
           '      break;\n'
           '    case ContentSettingsType::IRIS_GOOGLE_SIGNIN:\n'
           '      icon = show_blocked_badge ? &vector_icons::kAccountCircleOffIcon\n'
           '                                : &vector_icons::kAccountCircleIcon;\n'
           '      break;\n' + old)
    if s.count(old) != 1: die(p + ": default: NOTREACHED anchor not found exactly once (drift?)")
    open(p, "w").write(s.replace(old, new, 1)); print("OK   " + p + " : Iris row icons")
PY
echo "=== Page Info icons complete ==="
