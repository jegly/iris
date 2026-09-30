#!/usr/bin/env bash
# Iris — B13 build fix (2026-09-28). With enterprise_content_analysis=false but enterprise_cloud_content_analysis=true
# (kept on: gn asserts), the download bubble still calls enterprise_connectors::ShouldPromptReviewForDownload(), which
# common.h only declares under ENTERPRISE_CONTENT_ANALYSIS. The other callers (download_item_model.cc,
# downloads_list_tracker.cc) already guard it. Add a local "no review prompt" stub to the three unguarded bubble files
# (the admin review dialog cannot exist without content analysis, so false is the upstream behaviour).
# Per-file stub instead of common.h so only three files recompile. Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
ANCHOR = ('#if BUILDFLAG(ENTERPRISE_CLOUD_CONTENT_ANALYSIS)\n'
          '#include "chrome/browser/enterprise/connectors/common.h"\n'
          '#endif\n')
STUB = ('\n// Iris: content analysis is compiled out (apply-download-review-stub.sh).\n'
        '#if !BUILDFLAG(ENTERPRISE_CONTENT_ANALYSIS)\n'
        'namespace enterprise_connectors {\n'
        'inline bool ShouldPromptReviewForDownload(Profile*, const download::DownloadItem*) {\n'
        '  return false;\n'
        '}\n'
        '}  // namespace enterprise_connectors\n'
        '#endif\n')
for name in ("download_bubble_info_utils", "download_bubble_row_view_info", "download_bubble_security_view_info"):
    p = "chrome/browser/ui/download/%s.cc" % name
    s = open(p).read()
    if "apply-download-review-stub.sh" in s: print("SKIP already applied: " + p); continue
    if s.count(ANCHOR) != 1: die(p + ": include anchor not found exactly once (drift?)")
    open(p, "w").write(s.replace(ANCHOR, ANCHOR + STUB, 1)); print("OK   " + p + " : review stub")
PY
echo "=== download review stub complete ==="
