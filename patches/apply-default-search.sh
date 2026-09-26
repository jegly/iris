#!/usr/bin/env bash
# Iris — default search engine away from Google (verified against checkout 2026-09-25).
# Replaces the fallback/default search provider with DuckDuckGo, region-independent.
# Guarded multi-line replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
#
# MECHANISM (verified):
#   DefaultSearchManager::GetFallbackSearchEngine() -> Resolver::GetFallbackSearch()
#   -> TemplateURLPrepopulateData::GetPrepopulatedFallbackSearch(), which upstream calls
#   FindPrepopulatedEngineInternal(..., google.id, use_first_as_fallback=true): it looks
#   up google in the REGIONAL engine list and, failing that, returns the region's FIRST
#   engine (also Google for most regions). We instead build DuckDuckGo directly from its
#   PrepopulatedEngine definition, so the default is DDG regardless of detected country.
#
#   `duckduckgo` is in scope (namespace TemplateURLPrepopulateData, from the included
#   prepopulated_engines.h) and TemplateURLDataFromPrepopulatedEngine() is already
#   included via template_url_data_util.h — no new #include needed.
#
# TO USE A DIFFERENT ENGINE: change the single symbol `duckduckgo` below to another
#   built-in from prepopulated_engines.json: startpage, brave, ecosia, qwant, mojeek.
#
# CAVEAT (not fixed here): the engine LIST shown in chrome://settings/search still comes
#   from the regional list (google/bing/yahoo for the ZZ region), so DDG is the default
#   but may not appear as a *selectable* option in every region's dropdown. Making DDG
#   appear in the list is a separate edit to regional_settings.json (add "&duckduckgo").
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

# The engine to default to (a symbol from prepopulated_engines.h). Swap here.
ENGINE="${IRIS_SEARCH_ENGINE:-duckduckgo}"

flip_slurp() {
  local file="$1" re="$2" new="$3" marker="$4" n
  if grep -Fq -- "$marker" "$file"; then echo "SKIP already applied: $file"; return; fi
  n=$(RE="$re" perl -0777 -ne 'my $r=$ENV{RE}; my $c=()=/$r/g; print $c' "$file")
  if [ "$n" -eq 1 ]; then
    RE="$re" NEW="$new" perl -0777 -pi -e 'my($r,$w)=($ENV{RE},$ENV{NEW}); s/$r/$w/;' "$file"
    echo "OK   $file : default search -> $ENGINE"
  else
    echo "ERROR: expected exactly 1 match of pattern in $file (found $n; drift?)" >&2; exit 1
  fi
}

MARKER="return TemplateURLDataFromPrepopulatedEngine(${ENGINE});  // Iris: default search"
flip_slurp components/search_engines/template_url_prepopulate_data.cc \
  'return FindPrepopulatedEngineInternal\(prefs, regional_prepopulated_engines,\s*google\.id,\s*/\*use_first_as_fallback=\*/true\);' \
  "return TemplateURLDataFromPrepopulatedEngine(${ENGINE});  // Iris: default search" \
  "$MARKER"

echo "=== default search engine -> ${ENGINE} complete ==="
