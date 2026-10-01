#!/usr/bin/env bash
# Iris — stop the Google requests desktop Iris made at startup (found 2026-10-01 with a net-log probe of the shipped
# out/Linux build: fresh profile, every request pointed at a dead proxy, then mapped by traffic annotation).
# Both platforms (shared code). The old belief that --disable-background-networking stopped these was WRONG.
#  1) accounts.google.com/ListAccounts (annotation gaia_auth_list_accounts): GaiaCookieManagerService asked Google
#     which Google accounts are signed in to the web, even with browser sign-in off. Iris answers "no accounts"
#     itself: an empty response is a valid empty ListAccountsResponse (base64 "" -> empty proto). Signing in to
#     Google websites is unaffected.
#  2) clients2.google.com/time/1/current (network_time_component): Google network time. kNetworkTimeServiceQuerying
#     off everywhere (upstream already does this on ChromeOS); the system clock is used.
#  3) update.googleapis.com (update_client): the component updater. jegly 2026-10-01: keep ONLY security data.
#     CrxUpdateService::RegisterComponent() refuses every component except
#       hfnkpimlhhgieaddgfemjhofmfblmnib  CRLSet (Google's list of revoked certificates)
#       efniojlnjndmcbiieegkicadnoecjjef  PKI metadata (Certificate Transparency log list, key pins, Chrome Root
#                                         Store updates; CT/pinning enforcement stops after ~10 weeks without it)
#     Every registration (startup list and on-demand: Screen AI, speech, voices, hyphenation, ...) goes through
#     RegisterComponent, so this is the single gate. IDs = first 16 bytes of each installer's key hash, a-p encoded.
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

# 1) no ListAccounts request to Google
p = "components/signin/internal/identity_manager/gaia_cookie_manager_service.cc"
edit(p,
     "void GaiaCookieManagerService::StartFetchingListAccounts() {\n"
     "  gaia_auth_fetcher_ =\n"
     "      signin_client_->CreateGaiaAuthFetcher(this, requests_.front().source());\n"
     "  gaia_auth_fetcher_->StartListAccounts();\n"
     "}\n",
     "void GaiaCookieManagerService::StartFetchingListAccounts() {\n"
     "  // Iris: never ask accounts.google.com which Google accounts are signed in.\n"
     "  // An empty response is a valid, empty ListAccountsResponse (no accounts).\n"
     "  OnListAccountsSuccess(std::string());\n"
     "}\n",
     "  // Iris: never ask accounts.google.com", "no ListAccounts request")

# 2) no Google network time
p = "components/network_time/network_time_tracker.cc"
old = ("#if BUILDFLAG(IS_CHROMEOS) || BUILDFLAG(IS_IOS)\n"
       "BASE_FEATURE(kNetworkTimeServiceQuerying, base::FEATURE_DISABLED_BY_DEFAULT);\n"
       "#else\n"
       "BASE_FEATURE(kNetworkTimeServiceQuerying, base::FEATURE_ENABLED_BY_DEFAULT);\n"
       "#endif\n")
new = "BASE_FEATURE(kNetworkTimeServiceQuerying, base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: system clock\n"
edit(p, old, new, new, "network time off")

# 3) component updater: security data only
p = "components/component_updater/component_updater_service.cc"
old = ("  if (component.app_id.empty() || !component.version.IsValid() ||\n"
       "      !component.installer) {\n"
       "    return false;\n"
       "  }\n")
new = old + ("\n"
             "  // Iris: only security data from Google's component updater: CRLSet\n"
             "  // (revoked certificates) and PKI metadata (Certificate Transparency logs,\n"
             "  // key pins, Chrome Root Store). Everything else is refused.\n"
             "  if (component.app_id != \"hfnkpimlhhgieaddgfemjhofmfblmnib\" &&\n"
             "      component.app_id != \"efniojlnjndmcbiieegkicadnoecjjef\") {\n"
             "    VLOG(1) << \"Iris: component not allowed: \" << component.app_id;\n"
             "    return false;\n"
             "  }\n")
edit(p, old, new, "  // Iris: only security data from Google's component updater", "component allowlist")
PY
