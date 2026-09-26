#!/usr/bin/env bash
# Iris — remove the "AI" settings page/nav entry (verified against checkout 2026-09-25).
# Forces settings' `showAiPage` gate to false so the AI subpage + its nav item never render.
# Guarded multi-line replacement; idempotent; fails loudly on rebase drift.
# Run from Chromium src root (or pass it as $1). Copy-tested before landing.
#
# WHY force it (vs relying on the unbranded build):
#   showAiPage is OR'd from show_glic_section / show_ai_features_section /
#   enable_ai_mode_search / show_geic_section. In our unbranded build
#   (is_chrome_branded=false, no optimization-guide, use_on_device_model_service=false)
#   these are already false — but hardcoding the gate is durable across rebases and
#   feature-flag churn. The four sub-booleans stay used elsewhere (showGlicSettings,
#   showGeicSettings, showAiPageAiFeatureSection, enableAiModeSearchSetting) so this
#   does NOT create -Werror unused-variable failures (checked).
#
# NOTE: there is a second, dynamic path (settings_ui.cc, in an OnGlicSettingsChanged-
#   style update: `if (show_glic) update.Set("showAiPage", true);`). It is gated on Glic
#   being enabled, which requires branding/enterprise and is off in our build, so it
#   never fires. Left untouched to avoid editing inside a conditional; revisit if we ever
#   enable Glic.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"

# guarded multi-line (slurp) regex replace. Skips if the applied marker is already present.
flip_slurp() {
  local file="$1" re="$2" new="$3" marker="$4" n
  if grep -Fq -- "$marker" "$file"; then echo "SKIP already applied: $file"; return; fi
  n=$(RE="$re" perl -0777 -ne 'my $r=$ENV{RE}; my $c=()=/$r/g; print $c' "$file")
  if [ "$n" -eq 1 ]; then
    RE="$re" NEW="$new" perl -0777 -pi -e 'my($r,$w)=($ENV{RE},$ENV{NEW}); s/$r/$w/;' "$file"
    echo "OK   $file : showAiPage gate forced false"
  else
    echo "ERROR: expected exactly 1 match of pattern in $file (found $n; drift?)" >&2; exit 1
  fi
}

flip_slurp chrome/browser/ui/webui/settings/settings_ui.cc \
  'html_source->AddBoolean\("showAiPage",\s*[^;]*?\);' \
  'html_source->AddBoolean("showAiPage", false);  // Iris: AI settings page removed' \
  'html_source->AddBoolean("showAiPage", false);  // Iris: AI settings page removed'

echo "=== remove AI settings page complete ==="
