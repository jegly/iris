#!/usr/bin/env bash
# Iris — "Customize your toolbar" (Settings > Appearance; the Customize Chrome side panel) for Iris (0.0.0.7 item 12,
# jegly 2026-10-10: "missing out options in there and those stock icons need customising, also need to remove some
# things i.e like cast, send to device"; verified against 156.0.8078.11).
#  1. Iris's own buttons in the panel, as a first section "Iris": Shield, JavaScript, New identity, Lock. Each switch
#     is the same pref as the Appearance switches (iris.ui.toolbar_*); the panel follows pref changes made elsewhere;
#     "Reset to default" also turns them back on.
#  2. Not listed (Iris has no such feature or removed it): Cast (media router off), Send to your devices and Tabs from
#     other devices (no sync), Google Lens, Search Companion, Translate, the AI contextual-tasks button.
#  3. Stock icons in Iris's style: Tabler Icons outline (MIT, v3.34.0, tools/tabler-svgs, converted by
#     tools/svg_to_icon.py) replace the icons this build draws (rounded icons off = the "...Old" variants). They are
#     used wherever Chromium draws them (toolbar, menus, this panel):
#       home, forward/back arrows, split view, incognito (spy), passwords (key), payment methods (credit card),
#       addresses (map pin), bookmarks, reading list (list check), history, downloads, delete browsing data (trash),
#       print (printer), QR code, reading mode (book), copy link (link), task manager (activity), developer tools
#       (terminal), Chrome Labs (flask).
# Needs apply-toolbar-buttons.sh (the Iris buttons and their prefs) and apply-toolbar-icons.sh (kIris*Icon).
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (customize_toolbar_handler.o, its mojom, vector icons).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
for f in chrome/app/vector_icons/navigate_home_chrome_refresh_old.icon \
         components/vector_icons/forward_arrow_chrome_refresh_old.icon \
         components/vector_icons/back_arrow_chrome_refresh_old.icon \
         chrome/app/vector_icons/split_scene_old.icon \
         chrome/app/vector_icons/incognito_refresh_menu_old.icon \
         components/vector_icons/password_manager_old.icon \
         chrome/app/vector_icons/credit_card_chrome_refresh_old.icon \
         components/vector_icons/location_on_chrome_refresh_old.icon \
         chrome/app/vector_icons/bookmarks_side_panel_refresh_old.icon \
         chrome/app/vector_icons/reading_list_old.icon \
         components/vector_icons/history_chrome_refresh_old.icon \
         chrome/app/vector_icons/download_toolbar_button_chrome_refresh_old.icon \
         chrome/app/vector_icons/trash_can_refresh_old.icon \
         chrome/app/vector_icons/print_menu_old.icon \
         chrome/app/vector_icons/qr_code_chrome_refresh_old.icon \
         chrome/app/vector_icons/menu_book_chrome_refresh_old.icon \
         chrome/app/vector_icons/link_chrome_refresh_old.icon \
         components/vector_icons/table_chart.icon \
         chrome/app/vector_icons/developer_tools_old.icon \
         components/vector_icons/science_old.icon; do
  from="$DIR/src/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  [ -f "$f" ] || { echo "ERROR: $f not in the tree (drift: icon renamed?)" >&2; exit 1; }
  if cmp -s "$from" "$f"; then echo "SKIP up to date: $f"; else cp "$from" "$f"; echo "OK   $f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

D = "chrome/browser/ui/webui/side_panel/customize_chrome/customize_toolbar/"
M = D + "customize_toolbar.mojom"
edit(M, "  kShowTabsFromOtherDevices,\n};\n",
     "  kShowTabsFromOtherDevices,\n"
     "  // Iris's own toolbar buttons (apply-customize-toolbar.sh).\n"
     "  kIrisShield,\n  kIrisJavaScript,\n  kIrisNewIdentity,\n  kIrisLock,\n};\n",
     "kIrisShield,", "mojom: Iris actions")
edit(M, "  kTools,\n};\n",
     "  kTools,\n  kIris,  // Iris (apply-customize-toolbar.sh)\n};\n",
     "kIris,  // Iris", "mojom: Iris category")

H = D + "customize_toolbar_handler.h"
edit(H, "  void OnActionItemChanged();\n",
     "  void OnActionItemChanged();\n"
     "  // Iris: an Iris toolbar button was shown or hidden (apply-customize-toolbar.sh).\n"
     "  void OnIrisPinnedChanged(side_panel::customize_chrome::mojom::ActionId id,\n"
     "                           const char* pref);\n",
     "OnIrisPinnedChanged(", "header")

C = D + "customize_toolbar_handler.cc"
edit(C, "namespace {\n",
     "namespace {\n\n"
     "// Iris (apply-customize-toolbar.sh): Iris's toolbar buttons, shown or hidden\n"
     "// by the same prefs as the switches in Settings > Appearance.\n"
     "struct IrisButton {\n"
     "  side_panel::customize_chrome::mojom::ActionId id;\n"
     "  const char* name;\n"
     "  const char* pref;\n"
     "  const gfx::VectorIcon* icon;\n"
     "};\n"
     "constexpr auto kIrisButtons = std::to_array<IrisButton>({\n"
     "    {side_panel::customize_chrome::mojom::ActionId::kIrisShield, \"Shield\",\n"
     "     \"iris.ui.toolbar_shield\", &kIrisShieldIcon},\n"
     "    {side_panel::customize_chrome::mojom::ActionId::kIrisJavaScript,\n"
     "     \"JavaScript on this site\", \"iris.ui.toolbar_javascript\",\n"
     "     &kIrisJavascriptIcon},\n"
     "    {side_panel::customize_chrome::mojom::ActionId::kIrisNewIdentity,\n"
     "     \"New identity\", \"iris.ui.toolbar_new_identity\", &kIrisFlameIcon},\n"
     "    {side_panel::customize_chrome::mojom::ActionId::kIrisLock,\n"
     "     \"Lock Iris (while the app lock is on)\", \"iris.ui.toolbar_lock\",\n"
     "     &kIrisLockIcon},\n"
     "});\n\n"
     "// Iris: features Iris does not have or removed; not offered in the panel.\n"
     "bool IrisHidesAction(actions::ActionId id) {\n"
     "  switch (id) {\n"
     "    case kActionRouteMedia:                         // Cast\n"
     "    case kActionSendTabToSelf:                      // needs sync\n"
     "    case kActionSidePanelShowTabsFromOtherDevices:  // needs sync\n"
     "    case kActionSidePanelShowLensOverlayResults:    // Google Lens\n"
     "    case kActionSidePanelShowSearchCompanion:\n"
     "    case kActionShowTranslate:\n"
     "    case kActionSidePanelShowContextualTasks:       // AI\n"
     "      return true;\n"
     "    default:\n"
     "      return false;\n"
     "  }\n"
     "}\n",
     "constexpr auto kIrisButtons", "Iris buttons + hidden actions")
s = open(C).read()
if "#include <array>" not in s:
    edit(C, '#include "base/feature_list.h"\n', '#include <array>  // Iris\n\n#include "base/feature_list.h"\n',
         "#include <array>  // Iris", "<array>")
edit(C, "                          prefs::kPinSplitTabButton));\n}\n",
     "                          prefs::kPinSplitTabButton));\n"
     "  for (const IrisButton& button : kIrisButtons) {  // Iris\n"
     "    pref_change_registrar_.Add(\n"
     "        button.pref,\n"
     "        base::BindRepeating(&CustomizeToolbarHandler::OnIrisPinnedChanged,\n"
     "                            base::Unretained(this), button.id, button.pref));\n"
     "  }\n}\n",
     "&CustomizeToolbarHandler::OnIrisPinnedChanged", "watch Iris prefs")
edit(C, "  actions.push_back(std::move(split_tab_action));\n",
     "  actions.push_back(std::move(split_tab_action));\n\n"
     "  // Iris: its own toolbar buttons (apply-customize-toolbar.sh).\n"
     "  for (const IrisButton& button : kIrisButtons) {\n"
     "    actions.push_back(side_panel::customize_chrome::mojom::Action::New(\n"
     "        button.id, button.name, prefs()->GetBoolean(button.pref), false,\n"
     "        side_panel::customize_chrome::mojom::CategoryId::kIris,\n"
     "        GURL(webui::EncodePNGAndMakeDataURI(\n"
     "            ui::ImageModel::FromVectorIcon(*button.icon, icon_color_id)\n"
     "                .Rasterize(&provider),\n"
     "            scale_factor))));\n"
     "  }\n",
     "CategoryId::kIris,", "list Iris buttons")
edit(C, "        actions::ActionItem* const scope_action =\n",
     "        if (IrisHidesAction(id)) {  // Iris\n          return;\n        }\n"
     "        actions::ActionItem* const scope_action =\n",
     "if (IrisHidesAction(id)) {", "hide unsupported actions")
edit(C, "  std::vector<side_panel::customize_chrome::mojom::CategoryPtr> categories;\n",
     "  std::vector<side_panel::customize_chrome::mojom::CategoryPtr> categories;\n"
     "  // Iris: its own buttons first (apply-customize-toolbar.sh).\n"
     "  categories.push_back(side_panel::customize_chrome::mojom::Category::New(\n"
     "      side_panel::customize_chrome::mojom::CategoryId::kIris, \"Iris\"));\n",
     'CategoryId::kIris, "Iris"', "Iris category")
edit(C, "    bool pin) {\n  const std::optional<actions::ActionId> chrome_action =\n",
     "    bool pin) {\n"
     "  for (const IrisButton& button : kIrisButtons) {  // Iris\n"
     "    if (button.id == action_id) {\n"
     "      prefs()->SetBoolean(button.pref, pin);\n"
     "      return;\n"
     "    }\n"
     "  }\n"
     "  const std::optional<actions::ActionId> chrome_action =\n",
     "prefs()->SetBoolean(button.pref, pin);", "pin Iris buttons")
edit(C, "  std::move(callback).Run(!model_->IsDefault());\n",
     "  bool iris_customized = false;  // Iris: a hidden Iris button counts too\n"
     "  for (const IrisButton& button : kIrisButtons) {\n"
     "    iris_customized |= !prefs()->FindPreference(button.pref)->IsDefaultValue();\n"
     "  }\n"
     "  std::move(callback).Run(!model_->IsDefault() || iris_customized);\n",
     "iris_customized", "customized state")
edit(C, "void CustomizeToolbarHandler::ResetToDefault() {\n  model_->ResetToDefault();\n",
     "void CustomizeToolbarHandler::ResetToDefault() {\n  model_->ResetToDefault();\n"
     "  for (const IrisButton& button : kIrisButtons) {  // Iris\n"
     "    prefs()->ClearPref(button.pref);\n"
     "  }\n",
     "prefs()->ClearPref(button.pref);", "reset Iris buttons")
edit(C, "void CustomizeToolbarHandler::OnActionItemChanged() {\n",
     "void CustomizeToolbarHandler::OnIrisPinnedChanged(\n"
     "    side_panel::customize_chrome::mojom::ActionId id,\n"
     "    const char* pref) {\n"
     "  client_->SetActionPinned(id, prefs()->GetBoolean(pref));\n"
     "}\n\n"
     "void CustomizeToolbarHandler::OnActionItemChanged() {\n",
     "void CustomizeToolbarHandler::OnIrisPinnedChanged(", "Iris pref callback")
PY
echo "=== Customize your toolbar for Iris complete ==="
