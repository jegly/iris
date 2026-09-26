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
# Refreshing the lists later = re-run this, then re-run patches/apply-adblock.sh (copies the new files; only
# resources are rebuilt).
# Usage: build-ruleset.sh [--offline]   (--offline: reuse adblock/lists/*.txt instead of downloading)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${IRIS_SRC:-$HOME/Documents/chromium/src}"
CONV="$SRC/out/Default/ruleset_converter"
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

"$CONV" --input_format=filter-list --output_format=unindexed-ruleset \
  --input_files="$LISTS/easylist.txt,$LISTS/easyprivacy.txt" --output_file_url="$DIST/ruleset.pb.new" 2>"$HERE/converter-skipped.log"
[ -s "$DIST/ruleset.pb.new" ] || { echo "ERROR: converter produced an empty ruleset" >&2; exit 1; }
mv "$DIST/ruleset.pb.new" "$DIST/ruleset.pb"

SHA=$(sha256sum "$DIST/ruleset.pb" | cut -c1-12)
echo "iris-$(date -u +%Y%m%d)-$SHA" > "$DIST/version.txt"

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
} > "$DIST/LICENSE"

echo "skipped (unsupported) rules: $(grep -c 'rule_stream.cc' "$HERE/converter-skipped.log" || true) — see adblock/converter-skipped.log"
echo "OK   $DIST/ruleset.pb ($(stat -c %s "$DIST/ruleset.pb") bytes), version $(cat "$DIST/version.txt")"
echo "Next: ~/Documents/iris/patches/apply-adblock.sh"
