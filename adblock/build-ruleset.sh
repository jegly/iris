#!/usr/bin/env bash
# Iris — produce the bundled ad/tracker ruleset consumed by patches/apply-adblock.sh.
#   out: ~/Documents/iris/adblock/dist/{ruleset.pb, version.txt, LICENSE}
# Steps (run in jegly's own terminal — the agent's network is filtered):
#   1. needs the host tool:  cd ~/Documents/chromium/src && autoninja -C out/Default ruleset_converter
#      (//components/subresource_filter/tools:ruleset_converter — a small tool build, not the browser)
#   2. downloads EasyList + EasyPrivacy from easylist.to (HTTPS) into adblock/lists/
#   3. converts them to Chromium's unindexed-ruleset format. URL rules ONLY (--output_file_url): the RulesetService
#      indexes only url_rules() (ruleset_service.cc), so cosmetic rules would be ~1.2 MB of dead weight. Rules the
#      filter can't express ($document blocking, $redirect, $csp, $rewrite, #?#) are skipped -> converter-skipped.log
#   4. writes version.txt = iris-<UTC date>-<sha256 prefix of ruleset.pb> (a new list => new version => re-index)
#   5. EXTRA level (Settings -> "Block more ads and trackers"): downloads StevenBlack hosts, HaGeZi Pro, AdGuard DNS filter and
#      URLhaus hosts, merges them with prepare-extra-lists.py, converts EasyList + EasyPrivacy + those into ruleset-extra.pb
#      (+ version-extra.txt). One ruleset loads at a time (Chromium's filter has one), so Extra is a superset of Standard.
# Refreshing the lists later = re-run this, then re-run patches/apply-adblock.sh (copies the new files; only
# resources are rebuilt).
# Usage: build-ruleset.sh [--offline]   (--offline: reuse adblock/lists/*.txt instead of downloading)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${IRIS_SRC:-$HOME/Documents/chromium/src}"
CONV="${IRIS_CONV:-$SRC/out/Default/ruleset_converter}"; [ -x "$CONV" ] || CONV="$SRC/out/Linux/ruleset_converter"
LISTS="$HERE/lists"; DIST="$HERE/dist"
mkdir -p "$LISTS" "$DIST"
[ -x "$CONV" ] || { echo "ERROR: $CONV missing. Build it: cd $SRC && autoninja -C out/Default ruleset_converter" >&2; exit 1; }

if [ "${1:-}" != "--offline" ]; then
  for l in easylist easyprivacy; do
    curl -fsSL --proto '=https' --tlsv1.2 -o "$LISTS/$l.txt.new" "https://easylist.to/easylist/$l.txt"
    head -1 "$LISTS/$l.txt.new" | grep -q '^\[Adblock Plus' || { echo "ERROR: $l.txt does not look like a filter list" >&2; exit 1; }
    mv "$LISTS/$l.txt.new" "$LISTS/$l.txt"
  done
fi
for l in easylist easyprivacy; do [ -s "$LISTS/$l.txt" ] || { echo "ERROR: $LISTS/$l.txt missing" >&2; exit 1; }; done

if [ "${1:-}" != "--offline" ]; then
  get() { curl -fsSL --proto '=https' --tlsv1.2 -o "$LISTS/$1.new" "$2" && [ -s "$LISTS/$1.new" ] && mv "$LISTS/$1.new" "$LISTS/$1"; }
  get stevenblack-hosts.txt https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
  get hagezi-pro.txt https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt
  get adguard-dns.txt https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
  get urlhaus-hosts.txt https://urlhaus.abuse.ch/downloads/hostfile/
fi
for l in stevenblack-hosts hagezi-pro adguard-dns urlhaus-hosts; do [ -s "$LISTS/$l.txt" ] || { echo "ERROR: $LISTS/$l.txt missing" >&2; exit 1; }; done

"$CONV" --input_format=filter-list --output_format=unindexed-ruleset \
  --input_files="$LISTS/easylist.txt,$LISTS/easyprivacy.txt" --output_file_url="$DIST/ruleset.pb.new" 2>"$HERE/converter-skipped.log"
[ -s "$DIST/ruleset.pb.new" ] || { echo "ERROR: converter produced an empty ruleset" >&2; exit 1; }
mv "$DIST/ruleset.pb.new" "$DIST/ruleset.pb"

SHA=$(sha256sum "$DIST/ruleset.pb" | cut -c1-12)
echo "iris-$(date -u +%Y%m%d)-$SHA" > "$DIST/version.txt"

# --- Extra level: EasyList + EasyPrivacy + the merged extra lists ---
python3 "$HERE/prepare-extra-lists.py" "$LISTS/extra-merged.txt" "$LISTS/stevenblack-hosts.txt" "$LISTS/urlhaus-hosts.txt" \
  "$LISTS/hagezi-pro.txt" "$LISTS/adguard-dns.txt"
"$CONV" --input_format=filter-list --output_format=unindexed-ruleset \
  --input_files="$LISTS/easylist.txt,$LISTS/easyprivacy.txt,$LISTS/extra-merged.txt" --output_file_url="$DIST/ruleset-extra.pb.new" \
  2>"$HERE/converter-skipped-extra.log"
[ -s "$DIST/ruleset-extra.pb.new" ] || { echo "ERROR: converter produced an empty extra ruleset" >&2; exit 1; }
mv "$DIST/ruleset-extra.pb.new" "$DIST/ruleset-extra.pb"
SHAX=$(sha256sum "$DIST/ruleset-extra.pb" | cut -c1-12)
echo "iris-extra-$(date -u +%Y%m%d)-$SHAX" > "$DIST/version-extra.txt"

{
  echo "Iris bundles filter rules converted from the following lists (network rules only):"
  for l in easylist easyprivacy; do
    echo; echo "== $l.txt (https://easylist.to/) =="
    grep -m3 -E '^! (Title|Version|Last modified):' "$LISTS/$l.txt" || true
  done
  echo
  echo "EasyList and EasyPrivacy are written by The EasyList authors (https://easylist.to/)"
  echo "and dual-licensed under GPLv3 or later (https://www.gnu.org/licenses/gpl-3.0.html)"
  echo "and Creative Commons Attribution-ShareAlike 3.0 Unported"
  echo "(https://creativecommons.org/licenses/by-sa/3.0/)."
  echo
  echo "The optional \"Block more ads and trackers\" level also bundles (domain rules, network rules only):"
  for l in hagezi-pro adguard-dns; do
    echo; echo "== $l.txt =="
    grep -m4 -E '^! (Title|Homepage|License|Last modified):' "$LISTS/$l.txt" || true
  done
  echo
  echo "HaGeZi's DNS blocklists (https://github.com/hagezi/dns-blocklists) are licensed GPL-3.0."
  echo "The AdGuard DNS filter (https://github.com/AdguardTeam/AdGuardSDNSFilter) is licensed GPL-3.0."
  echo "abuse.ch URLhaus host file (https://urlhaus.abuse.ch/), free to use (CC0)."
  echo
  echo "StevenBlack/hosts (https://github.com/StevenBlack/hosts), MIT License:"
  echo "Copyright (c) Steven Black"
  echo "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated"
  echo "documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation"
  echo "the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to"
  echo "permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright"
  echo "notice and this permission notice shall be included in all copies or substantial portions of the Software."
  echo "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO"
  echo "THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE"
  echo "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,"
  echo "TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
} > "$DIST/LICENSE"

echo "skipped (unsupported) rules: $(grep -c 'rule_stream.cc' "$HERE/converter-skipped.log" || true) — see adblock/converter-skipped.log"
echo "OK   $DIST/ruleset.pb ($(stat -c %s "$DIST/ruleset.pb") bytes), version $(cat "$DIST/version.txt")"
echo "OK   $DIST/ruleset-extra.pb ($(stat -c %s "$DIST/ruleset-extra.pb") bytes), version $(cat "$DIST/version-extra.txt")"
echo "Next: ~/Documents/iris/patches/apply-adblock.sh and apply-adblock-extra.sh"
