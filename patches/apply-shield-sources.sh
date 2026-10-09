#!/usr/bin/env bash
# Iris — shield counter, part 1: expose the numbers Chromium already collects (jegly 2026-10-09: shield with a blocked
# count like Brave's; Brave's own code was read first: its page total is the sum of per-tab blocked-URL lists for
# ads, HTTPS upgrades, scripts and fingerprinting, collected by events from its network layer / renderer).
# Chromium's ad blocker (subresource filter) blocks inside the renderer and sends one statistics message per document
# when it finishes loading; the browser sums it across frames (PageLoadStatistics) but only for UMA.
#  1. PageLoadStatistics::num_loads_disallowed(): the page's blocked-request total (ads + trackers from the filter lists).
#  2. PageSpecificContentSettings::GetBlockedCookieCount(): distinct cookies (domain|name|path) whose access was blocked
#     on this page (third-party cookies etc.), counted where OnCookiesAccessed() already sees details.blocked_by_policy.
# Read by chrome/browser/iris/iris_shield_stats.* (apply-shield-stats.sh). No behaviour change.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (page_load_statistics.o, page_specific_content_settings.o).
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
edit("components/subresource_filter/content/browser/page_load_statistics.h",
     "  void OnDidFinishLoad(bool record_incognito_metrics = false);\n",
     "  void OnDidFinishLoad(bool record_incognito_metrics = false);\n\n"
     "  // Iris: requests the ad blocker blocked on this page (all frames), for the\n"
     "  // toolbar shield (apply-shield-sources.sh).\n"
     "  int num_loads_disallowed() const {\n"
     "    return aggregated_document_statistics_.num_loads_disallowed;\n  }\n",
     "int num_loads_disallowed() const", "ads: blocked total accessor")
H = "components/content_settings/browser/page_specific_content_settings.h"
edit(H, "  bool IsContentBlocked(ContentSettingsType content_type) const;\n",
     "  bool IsContentBlocked(ContentSettingsType content_type) const;\n\n"
     "  // Iris: distinct cookies whose access was blocked on this page, for the\n"
     "  // toolbar shield (apply-shield-sources.sh).\n"
     "  int GetBlockedCookieCount() const {\n"
     "    return static_cast<int>(iris_blocked_cookie_keys_.size());\n  }\n",
     "GetBlockedCookieCount() const", "cookies: accessor")
s = open(H).read()
if "#include <set>" not in s:
    edit(H, "#include <memory>\n", "#include <memory>\n#include <set>  // Iris\n#include <string>  // Iris\n",
         "#include <set>  // Iris", "cookies: includes")
edit(H, "  std::unique_ptr<BrowsingDataModel> blocked_browsing_data_model_;\n",
     "  std::unique_ptr<BrowsingDataModel> blocked_browsing_data_model_;\n"
     "  std::set<std::string> iris_blocked_cookie_keys_;  // Iris: see GetBlockedCookieCount()\n",
     "iris_blocked_cookie_keys_;", "cookies: member")
edit("components/content_settings/browser/page_specific_content_settings.cc",
     "  if (details.blocked_by_policy) {\n    OnContentBlocked(ContentSettingsType::COOKIES);\n  } else {\n",
     "  if (details.blocked_by_policy) {\n"
     "    for (const auto& cookie_with_access_result :\n"
     "         details.cookie_access_result_list) {\n"
     "      const auto& cookie = cookie_with_access_result.cookie;\n"
     "      iris_blocked_cookie_keys_.insert(cookie.Domain() + \"|\" + cookie.Name() +\n"
     "                                       \"|\" + cookie.Path());  // Iris\n"
     "    }\n"
     "    OnContentBlocked(ContentSettingsType::COOKIES);\n  } else {\n",
     "iris_blocked_cookie_keys_.insert(", "cookies: count blocked")
PY
echo "=== shield sources complete ==="
