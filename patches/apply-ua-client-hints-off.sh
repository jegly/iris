#!/usr/bin/env bash
# Iris — never send UA client hints: (1) not the default low-entropy ones (Sec-CH-UA, Sec-CH-UA-Mobile, Sec-CH-UA-Platform)
# on every request (approved by jegly 2026-09-26; verified against checkout 2026-09-26).
# Consistent with apply-fingerprint-apis.sh (navigator.userAgentData removed): Iris then looks like Firefox/Safari,
# which never sent these. The classic User-Agent header is unchanged.
#
# MECHANISM (single point of truth): blink::IsClientHintSentByDefault() in
# third_party/blink/common/client_hints/client_hints.cc returns true for kSaveData, kUA, kUAMobile, kUAPlatform.
# Every sender consults it:
#   - browser navigations:        content/browser/client_hints/client_hints.cc ShouldAddClientHint()
#   - renderer subresources:      third_party/blink/renderer/core/loader/frame_fetch_context.cc ShouldSendClientHint()
#   - prefetch:                   content/browser/preloading/prefetch/prefetch_resource_request_utils.cc
#   - cross-origin redirect strip: FindClientHintsToRemove() (same file) — now strips them too unless policy allows.
# Only the three UA cases are removed; kSaveData stays (it is only sent when the user enables data saver).
# PART 2 (jegly 2026-09-26: "block fully"): sites cannot OPT IN either. Every opt-in path resolves hint names through
# network's GetDecodeMap() (services/network/public/cpp/client_hints.cc): ParseClientHintsHeader (Accept-CH header,
# <meta http-equiv="accept-ch">, Critical-CH) and ParseClientHintToDelegatedThirdPartiesHeader (delegate-ch). The
# sec-ch-ua* names are left out of that decode map, so a UA hint can never be enabled -> never sent. The type->name
# map (used to strip headers) is untouched. Guard: exactly the 11 UA hints start with "sec-ch-ua".
# Result: Iris never sends any Sec-CH-UA* header (Firefox/Safari behaviour).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "third_party/blink/common/client_hints/client_hints.cc"
s = open(p).read()
old = ("    case network::mojom::WebClientHintsType::kSaveData:\n"
       "    case network::mojom::WebClientHintsType::kUA:\n"
       "    case network::mojom::WebClientHintsType::kUAMobile:\n"
       "    case network::mojom::WebClientHintsType::kUAPlatform:\n"
       "      return true;")
new = ("    case network::mojom::WebClientHintsType::kSaveData:\n"
       "      // Iris: Sec-CH-UA / -Mobile / -Platform not sent by default (Firefox/Safari-like).\n"
       "      return true;")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: IsClientHintSentByDefault body changed (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : UA client hints no longer sent by default")
PY
python3 - <<'PY'
import re, sys
p = "services/network/public/cpp/client_hints.cc"
s = open(p).read()
names = re.findall(r'"(sec-ch-[a-z0-9-]*)"', s[s.find("MakeClientHintToNameMap"):s.find("GetClientHintToNameMap()")])
ua = sorted(n for n in names if n.startswith("sec-ch-ua"))
if len(ua) != 11 or not all(n == "sec-ch-ua" or n.startswith("sec-ch-ua-") for n in ua):
    sys.stderr.write(f"ERROR: {p}: UA hint names changed ({ua}) — re-check the prefix filter\n"); sys.exit(1)
old = ("    const auto& type = elem.first;\n"
       "    const auto& header = elem.second;\n"
       "    result.insert(std::make_pair(header, type));\n")
new = ("    const auto& type = elem.first;\n"
       "    const auto& header = elem.second;\n"
       "    // Iris: User-Agent client hints (sec-ch-ua*) can never be opted into via\n"
       "    // Accept-CH, Critical-CH or <meta> accept-ch / delegate-ch.\n"
       "    if (header.starts_with(\"sec-ch-ua\")) {\n"
       "      continue;\n"
       "    }\n"
       "    result.insert(std::make_pair(header, type));\n")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: MakeDecodeMap body changed (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : UA client hints cannot be opted into")
PY
echo "=== UA client hints (default) off complete ==="
