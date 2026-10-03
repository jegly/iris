#!/usr/bin/env bash
# Iris — no remote debugging of the real profile (jegly 2026-10-03; verified against the 156.0.8073.0 sources).
# Before: any program on the machine could start Iris with --remote-debugging-port / --remote-debugging-pipe and read
# every cookie and page of the user's profile over DevTools (the infostealer technique). Google Chrome refuses that on
# the default user-data-dir since M136, but chrome/browser/devtools/remote_debugging_server.cc only does so
# `#if BUILDFLAG(GOOGLE_CHROME_BRANDING)`; Chromium-branded builds (Iris) leave it to a testing-only global.
# After: Iris behaves like Google Chrome: both switches are ignored for the default profile
# (NotStartedReason::kDisabledByDefaultUserDataDir). Debugging still works with a separate profile:
#   iris --user-data-dir=/tmp/iris-debug --remote-debugging-port=9222      (headless tests: same)
# chrome://inspect "approval mode" (each connection approved by the user) is a different path and unchanged.
# STATUS 2026-10-03: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/devtools/remote_debugging_server.cc"
s = open(p).read()
MARK = "// Iris: like Google Chrome, never on the default profile"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
old = ("#else\n"
       "  const bool default_user_data_dir_check_enabled =\n"
       "      g_enable_default_user_data_dir_check_for_chromium_branding_for_testing;\n"
       "#endif\n")
new = ("#else\n"
       "  // Iris: like Google Chrome, never on the default profile (infostealers\n"
       "  // use remote debugging to read cookies). Use --user-data-dir to debug.\n"
       "  constexpr bool default_user_data_dir_check_enabled = true;\n"
       "  (void)g_enable_default_user_data_dir_check_for_chromium_branding_for_testing;\n"
       "#endif\n")
for guard in ("if (command_line.HasSwitch(switches::kRemoteDebuggingPipe)) {",
              "IsRemoteDebuggingAllowed(is_default_user_data_dir, local_state);"):
    if guard not in s: die("%s: expected '%s' (port/pipe no longer go through the check?)" % (p, guard))
if s.count(old) != 1: die("%s: Chromium-branding branch of the default-user-data-dir check not found (drift?)" % p)
open(p, "w").write(s.replace(old, new, 1))
print("OK   %s : remote debugging refused on the default profile" % p)
PY
echo "=== remote debugging guard complete ==="
