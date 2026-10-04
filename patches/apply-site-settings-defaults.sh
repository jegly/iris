#!/usr/bin/env bash
# Iris — Site settings defaults (jegly 2026-10-05, from the Android Site settings screen; verified against the
# 156.0.8073.0 and 156.0.8078.9 sources). components/content_settings/core/browser/content_settings_registry.cc:
#  - Auto-verify (ANTI_ABUSE, Private State Tokens: sites exchange tokens to vouch that you're not a bot)
#    ALLOW -> BLOCK.
#  - Protected content (PROTECTED_MEDIA_IDENTIFIER: a device identifier for DRM licences) ALLOW -> ASK on Android
#    (sites must ask; DRM video still works when you allow it). Not registered on Linux; other platforms unchanged
#    (ASK is not a valid value there).
#  - JavaScript optimisation (JAVASCRIPT_OPTIMIZER) ALLOW -> BLOCK, so Settings shows what Iris really does: Iris runs
#    every site without JIT (apply-jitless-runtime.sh, JAVASCRIPT_JIT = BLOCK) but this page said "Speed up sites ...
#    less resistant to attacks". No change in behaviour (JIT is already off); per-site exceptions still possible.
# Desktop + Android. Needs apply-iris-permissions.sh (it inserts registrations just before JAVASCRIPT_OPTIMIZER; this
# script anchors on the lines after that point).
# STATUS 2026-10-05: copy-tested only, NOT compile-proven (content_settings_registry.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "components/content_settings/core/browser/content_settings_registry.cc"
s = open(p).read()
MARK = "// Iris: Auto-verify blocked"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
EDITS = [
    ('  Register(ContentSettingsType::ANTI_ABUSE, "anti-abuse", CONTENT_SETTING_ALLOW,\n',
     '  // Iris: Auto-verify blocked by default (apply-site-settings-defaults.sh).\n'
     '  Register(ContentSettingsType::ANTI_ABUSE, "anti-abuse", CONTENT_SETTING_BLOCK,\n',
     "Auto-verify -> BLOCK"),
    ('  Register(ContentSettingsType::PROTECTED_MEDIA_IDENTIFIER,\n'
     '           "protected-media-identifier", CONTENT_SETTING_ALLOW,\n',
     '  Register(ContentSettingsType::PROTECTED_MEDIA_IDENTIFIER,\n'
     '           "protected-media-identifier",\n'
     '#if BUILDFLAG(IS_ANDROID)\n'
     '           CONTENT_SETTING_ASK,  // Iris: sites must ask\n'
     '#else\n'
     '           CONTENT_SETTING_ALLOW,\n'
     '#endif\n',
     "Protected content -> ASK (Android)"),
    ('  Register(ContentSettingsType::JAVASCRIPT_OPTIMIZER, "javascript-optimizer",\n'
     '           CONTENT_SETTING_ALLOW, WebsiteSettingsInfo::UNSYNCABLE,\n',
     '  Register(ContentSettingsType::JAVASCRIPT_OPTIMIZER, "javascript-optimizer",\n'
     '           CONTENT_SETTING_BLOCK,  // Iris: matches JIT off (jitless)\n'
     '           WebsiteSettingsInfo::UNSYNCABLE,\n',
     "JavaScript optimisation -> BLOCK"),
]
for old, new, what in EDITS:
    if s.count(old) != 1: die("%s: %s anchor not found exactly once (drift?)" % (p, what))
for old, new, what in EDITS:
    s = s.replace(old, new, 1); print("OK   %s : %s" % (p, what))
open(p, "w").write(s)
PY
echo "=== site settings defaults complete ==="
