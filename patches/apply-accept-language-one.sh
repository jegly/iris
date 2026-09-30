#!/usr/bin/env bash
# Iris — Accept-Language = ONE language (found by the self-test in jegly's window 2026-09-27: "en-US,en;q=0.9";
# verified against this checkout).
# The network-context default header (every request without its own header: subresources, fetch, most navigations)
# comes from ComputeAcceptLanguageFromPref() in chrome/browser/net/profile_network_context_service.cc:
# ExpandLanguageList() adds the base language ("en-US" -> "en-US,en") and GenerateAcceptLanguageHeader() adds
# q-values. kReduceAcceptLanguage (apply-degoogle-prefs.sh) only rewrites some navigation headers, so the claim
# "reduced to one value" was not true on the wire.
# Iris sends only the user's FIRST language, unexpanded, no q-value: "en-US". navigator.languages already reports the
# same single value; the user still chooses it (Settings -> Languages, first entry). Empty pref -> upstream behaviour.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "chrome/browser/net/profile_network_context_service.cc"
s = open(p).read()
old = ("std::string ComputeAcceptLanguageFromPref(const std::string& language_pref) {\n"
       "  std::string accept_languages_str =\n"
       "      net::HttpUtil::ExpandLanguageList(language_pref);\n"
       "  return net::HttpUtil::GenerateAcceptLanguageHeader(accept_languages_str);\n"
       "}\n")
new = ("std::string ComputeAcceptLanguageFromPref(const std::string& language_pref) {\n"
       "  // Iris: send only the user's first language, unexpanded and without\n"
       "  // q-values (less fingerprinting entropy than the full list).\n"
       "  std::string_view first = base::TrimWhitespaceASCII(\n"
       "      std::string_view(language_pref).substr(0, language_pref.find(',')),\n"
       "      base::TRIM_ALL);\n"
       "  if (!first.empty()) {\n"
       "    return std::string(first);\n"
       "  }\n"
       "  std::string accept_languages_str =\n"
       "      net::HttpUtil::ExpandLanguageList(language_pref);\n"
       "  return net::HttpUtil::GenerateAcceptLanguageHeader(accept_languages_str);\n"
       "}\n")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write("ERROR: %s: ComputeAcceptLanguageFromPref changed (drift?)\n" % p); sys.exit(1)
if '#include "base/strings/string_util.h"' not in s: sys.stderr.write("ERROR: string_util.h no longer included\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : Accept-Language = first language only")
PY
# 2026-09-27 (same day, runtime test): the header on the wire was STILL "en-US,en;q=0.9". Upstream's "reduced"
# Accept-Language is the first language EXPANDED again, in two places that override the network default:
#  - navigations: content/public/browser/reduce_accept_language_utils.cc AddNavigationRequestAcceptLanguageHeaders
#  - requests from a page (fetch, scripts, images): Blink FrameFetchContext::GetReducedAcceptLanguage
# Both now send the reduced language as-is ("en-US").
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, label):
    s = open(p).read()
    if new in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new)); print("OK   %s : %s" % (p, label))
edit("content/public/browser/reduce_accept_language_utils.cc",
     "  if (reduced_accept_language) {\n"
     "    std::string expanded_language_list =\n"
     "        net::HttpUtil::ExpandLanguageList(reduced_accept_language.value());\n"
     "    headers->SetHeader(\n"
     "        net::HttpRequestHeaders::kAcceptLanguage,\n"
     "        net::HttpUtil::GenerateAcceptLanguageHeader(expanded_language_list));\n"
     "  }\n",
     "  if (reduced_accept_language) {\n"
     "    // Iris: the single reduced language as-is (upstream expands it,\n"
     "    // \"en-US\" -> \"en-US,en;q=0.9\").\n"
     "    headers->SetHeader(net::HttpRequestHeaders::kAcceptLanguage,\n"
     "                       reduced_accept_language.value());\n"
     "  }\n",
     "navigation header = reduced language only")
edit("third_party/blink/renderer/core/loader/frame_fetch_context.cc",
     "  if (override_accept_language.empty()) {\n"
     "    String expanded_language = network_utils::ExpandLanguageList(\n"
     "        frame->GetReducedAcceptLanguage().GetString());\n"
     "    return network_utils::GenerateAcceptLanguageHeader(expanded_language);\n"
     "  }\n",
     "  if (override_accept_language.empty()) {\n"
     "    // Iris: the single reduced language as-is (not expanded).\n"
     "    return frame->GetReducedAcceptLanguage().GetString();\n"
     "  }\n",
     "page request header = reduced language only")
PY
echo "=== Accept-Language one value complete ==="
