#!/usr/bin/env bash
# Iris — no crash dumps on disk (jegly 2026-10-08: hardening round, on by default; verified against 156.0.8078.11).
# Finding: the unbranded build never UPLOADS crash reports (GetCollectStatsConsent() is false), but Crashpad is still
# started on Linux and Android (chrome_main_delegate.cc) and its handler writes every crash and DumpWithoutCrashing()
# report into the profile ("Crash Reports" database). A minidump holds process memory: URLs, page text, form data.
# Crashpad itself cannot be skipped: child processes (zygote path) expect its socket descriptor and would die.
# Fix: the handler's one write point - CrashReportExceptionHandler::HandleExceptionWithConnection()
# (third_party/crashpad/crashpad/handler/linux/, used by BOTH Linux and Android) - no longer writes the minidump to the
# database (or log); the snapshot only ever exists in the handler's memory. The crashed process still exits normally.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (crashpad handler: chrome_crashpad_handler / libcrashpad).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/crashpad/crashpad/handler/linux/crash_report_exception_handler.cc"
s = open(p).read()
MARK = "// Iris: no crash dumps on disk"
if MARK in s: print("SKIP already applied: " + p); sys.exit(0)
old = ("  return write_minidump_to_database_\n"
       "             ? WriteMinidumpToDatabase(process_snapshot.get(),\n"
       "                                       sanitized_snapshot.get(),\n"
       "                                       write_minidump_to_log_,\n"
       "                                       local_report_id)\n"
       "             : WriteMinidumpToLog(process_snapshot.get(),\n"
       "                                  sanitized_snapshot.get());\n"
       "}\n")
new = ("  " + MARK + " (apply-no-crash-dumps.sh): a minidump holds process\n"
       "  // memory (URLs, page text, form data). Iris never uploads reports, so it\n"
       "  // never writes them either; the snapshot is dropped here.\n"
       "  return false;\n"
       "}\n")
if s.count(old) != 1:
    sys.stderr.write("ERROR: %s: minidump write anchor not found exactly once (drift?)\n" % p); sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
print("OK   " + p)
PY
echo "=== no crash dumps complete ==="
