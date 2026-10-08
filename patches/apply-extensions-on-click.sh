#!/usr/bin/env bash
# Iris — new extensions get site access "on click" by default (jegly 2026-10-08: hardening round, on by default;
# extensions stay allowed - decision 2026-09-26; verified against 156.0.8078.11).
# Upstream already implements this behind extensions_features::kAllowWithholdingExtensionPermissionsOnInstall
# (disabled by default): the install dialog gets a checkbox (IDS_EXTENSION_PROMPT_GRANT_PERMISSIONS_CHECKBOX,
# unchecked) and, unless the user ticks it, CrxInstaller installs with Extension::WITHHOLD_PERMISSIONS, i.e. the
# extension's host permissions are withheld and it runs on a site only when the user clicks it / grants that site
# (extension_install_dialog_view.cc OnDialogAccepted, install_prompt_data.cc ShouldWithheldPermissionsOnDialogAccept).
# Iris: that feature enabled by default. Only affects new installs through the dialog; existing extensions keep
# their current site access. Desktop only (Android Iris has no extensions UI).
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (extensions/common extension_features.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "extensions/common/extension_features.cc"
s = open(p).read()
old = "BASE_FEATURE(kAllowWithholdingExtensionPermissionsOnInstall,\n             base::FEATURE_DISABLED_BY_DEFAULT);\n"
new = ("// Iris: new extensions run on a site only after a click (apply-extensions-on-click.sh).\n"
       "BASE_FEATURE(kAllowWithholdingExtensionPermissionsOnInstall,\n             base::FEATURE_ENABLED_BY_DEFAULT);\n")
if "apply-extensions-on-click.sh" in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: feature definition not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new, 1)); print("OK   " + p)
PY
echo "=== extensions on click complete ==="
