#!/usr/bin/env bash
# Iris — Android: build with enable_vr = false (2026-10-01).
# build/args-android.gn turns VR/XR off (enable_vr/openxr/cardboard/arcore = false). In this Chromium the omnibox
# vector icons (AutocompleteMatch::GetVectorIcon, OmniboxAction::GetVectorIcon) exist only when
# (!is_android || enable_vr), but two always-built callers use them unguarded, so the Android build fails
# ("no member named 'GetVectorIcon'"). Upstream never builds Android with VR off. Guard the two callers with the
# same condition instead of turning VR back on. Android's omnibox is drawn in Java and does not use these icons;
# with VR off they get no icon (empty image / empty icon path). Linux is unaffected (the condition is true there).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
COND = "#if !BUILDFLAG(IS_ANDROID) || BUILDFLAG(ENABLE_VR)  // Iris: no omnibox vector icons without VR\n"
INC = '#include "components/omnibox/browser/buildflags.h"  // Iris: ENABLE_VR\n'
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

# 1. OmniboxEditModel::GetMatchIcon: the final vector-icon fallback.
p = "chrome/browser/ui/omnibox/omnibox_edit_model.cc"
edit(p, '#include "build/build_config.h"\n',
     '#include "build/build_config.h"\n' + INC, INC, "include omnibox buildflags")
edit(p,
     "  bool is_starred_match = IsStarredMatch(match);\n"
     "  const auto& vector_icon_type = match.GetVectorIcon(is_starred_match, turl);\n"
     "\n"
     "  return controller_->client()->GetSizedIcon(vector_icon_type,\n"
     "                                             vector_icon_color);\n"
     "}\n",
     COND +
     "  bool is_starred_match = IsStarredMatch(match);\n"
     "  const auto& vector_icon_type = match.GetVectorIcon(is_starred_match, turl);\n"
     "\n"
     "  return controller_->client()->GetSizedIcon(vector_icon_type,\n"
     "                                             vector_icon_color);\n"
     "#else\n"
     "  return gfx::Image();\n"
     "#endif\n"
     "}\n",
     COND, "GetMatchIcon vector-icon fallback")

# 2. SearchboxHandler::CreateAutocompleteMatch: match icon path + action icon path.
p = "chrome/browser/ui/webui/cr_components/searchbox/searchbox_handler.cc"
edit(p, '#include "build/branding_buildflags.h"\n',
     '#include "build/branding_buildflags.h"\n' + INC, INC, "include omnibox buildflags")
old = ("  const bool is_bookmarked =\n"
       "      bookmark_model->IsBookmarked(match.destination_url);\n")
edit(p, old, COND + old, COND + old, "match icon path")
edit(p,
     "  mojom_match->icon_path = AutocompleteIconToResourceName(\n"
     "      match.GetVectorIcon(is_bookmarked, associated_keyword_turl));\n",
     "  mojom_match->icon_path = AutocompleteIconToResourceName(\n"
     "      match.GetVectorIcon(is_bookmarked, associated_keyword_turl));\n"
     "#endif  // Iris\n",
     "associated_keyword_turl));\n#endif  // Iris\n", "match icon path (end)")
old = "        icon_path = AutocompleteIconToResourceName(action->GetVectorIcon());\n"
edit(p, old, COND + old + "#endif  // Iris\n", COND + old, "action icon path")
PY
