#!/usr/bin/env bash
# Iris — B9 glass look (2026-09-28): ON by default since 2026-09-30 (jegly), toggle to turn off. Settings -> Appearance -> "Glass look".
# The browser window stays opaque (see-through-to-wallpaper would need window translucency in Views: fragile,
# not done). Inside Iris's own pages (Settings, History, Downloads, Extensions, ... = every WebUI that loads
# chrome://theme/colors.css) the page gets a soft two-colour glow from the current palette and the cards become
# translucent frosted panels (backdrop blur) over it.
#  - Profile pref iris.glass.enabled (default true since 2026-09-30), allowlisted for Settings.
#  - ThemeSource::SendColorsCss appends the glass rules when the pref is on (not for shadow-host sheets).
#  - ThemeService treats the pref like a colour change -> open pages refresh at once.
#  - settings-section cards use --iris-glass-filter / --iris-glass-border (none unless glass is on).
#  - Label: re-uses IDS_SETTINGS_IRIS_APP_LOCK_AFTER (no idle re-lock in Iris: jegly 2026-09-28, the app lock is
#    only at start), its text changed to "Glass look". A text-only change avoids a new message ID = no rebuild of
#    everything that includes the generated string header.
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

# 1. pref
edit("chrome/browser/prefs/browser_prefs.cc",
     "  IrisShredder::RegisterProfilePrefs(registry);  // Iris (B7)\n",
     "  IrisShredder::RegisterProfilePrefs(registry);  // Iris (B7)\n"
     "  registry->RegisterBooleanPref(\"iris.glass.enabled\", true);  // Iris (B9 glass)\n",
     "iris.glass.enabled", "register pref (run apply-shredder.sh first)")

# 1b. default ON (jegly 2026-09-30) — upgrades a tree patched while glass was opt-in.
p = "chrome/browser/prefs/browser_prefs.cc"
s = open(p).read()
off = '  registry->RegisterBooleanPref("iris.glass.enabled", false);  // Iris (B9 glass)\n'
if off in s:
    open(p, "w").write(s.replace(off, off.replace("false", "true"), 1)); print("OK   %s : glass on by default" % p)
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.shredding.enabled\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.shredding.enabled\"] = settings_api::PrefType::kBoolean;\n"
     "  // Iris (B9): Settings -> Appearance -> \"Glass look\".\n"
     "  (*s_allowlist)[\"iris.glass.enabled\"] = settings_api::PrefType::kBoolean;\n",
     "iris.glass.enabled", "settings may read/write the pref")

# 2. label (text-only change of an unused Iris string)
p = "chrome/app/settings_strings.grdp"
s = open(p).read()
old = ('  <message name="IDS_SETTINGS_IRIS_APP_LOCK_AFTER" desc="Iris: setting for how long until Iris locks again.">\n'
       '    Lock again after\n')
new = ('  <message name="IDS_SETTINGS_IRIS_APP_LOCK_AFTER" desc="Iris: toggle for the translucent glass look of the built-in pages (re-used message; there is no re-lock setting).">\n'
       '    Glass look\n')
if new in s: print("SKIP already applied: %s (label)" % p)
elif s.count(old) == 1: open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : label 'Glass look'" % p)
else: die(p + ": IDS_SETTINGS_IRIS_APP_LOCK_AFTER not found (run apply-iris-permissions.sh first)")
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"irisShredding\", IDS_SETTINGS_IRIS_SHREDDING},  // Iris (B7)\n",
     "      {\"irisShredding\", IDS_SETTINGS_IRIS_SHREDDING},  // Iris (B7)\n"
     "      {\"irisGlass\", IDS_SETTINGS_IRIS_APP_LOCK_AFTER},  // Iris (B9 glass)\n",
     "\"irisGlass\"", "string registered")

# 3. toggle under the theme rows
edit("chrome/browser/resources/settings/appearance_page/appearance_page.html.ts",
     '      <cr-link-row id="customizeToolbar"\n',
     '      <!-- Iris (B9): glass look, off by default (apply-glass.sh) -->\n'
     '      <settings-toggle-button id="irisGlassToggle" class="hr"\n'
     '          pref-key="iris.glass.enabled"\n'
     '          label="$i18n{irisGlass}">\n'
     '      </settings-toggle-button>\n'
     '      <cr-link-row id="customizeToolbar"\n',
     "irisGlassToggle", "Appearance toggle")

# 4. live refresh
edit("chrome/browser/themes/theme_service.cc",
     "  pref_change_registrar_.Add(\n"
     "      prefs::kUserColor, base::BindRepeating(&ThemeService::NotifyThemeChanged,\n"
     "                                             base::Unretained(this)));\n",
     "  pref_change_registrar_.Add(\n"
     "      prefs::kUserColor, base::BindRepeating(&ThemeService::NotifyThemeChanged,\n"
     "                                             base::Unretained(this)));\n"
     "  // Iris (B9 glass): open built-in pages re-fetch colors.css.\n"
     "  pref_change_registrar_.Add(\n"
     "      \"iris.glass.enabled\",\n"
     "      base::BindRepeating(&ThemeService::NotifyThemeChanged,\n"
     "                          base::Unretained(this)));\n",
     "Iris (B9 glass)", "refresh on toggle")

# 5. the glass rules in colors.css
t = "chrome/browser/ui/webui/theme_source.cc"
edit(t, "  if (!css_content) {\n    std::move(callback).Run(nullptr);\n    return;\n  }\n\n"
        "  std::move(callback).Run(\n",
     "  if (!css_content) {\n    std::move(callback).Run(nullptr);\n    return;\n  }\n\n"
     "  // Iris (B9 glass, apply-glass.sh): translucent frosted cards over a soft\n"
     "  // glow from the current palette. Off by default.\n"
     "  std::string shadow_host;\n"
     "  if (profile_->GetOriginalProfile()->GetPrefs()->GetBoolean(\n"
     "          \"iris.glass.enabled\") &&\n"
     "      !(net::GetValueForKeyInQuery(url, \"shadow_host\", &shadow_host) &&\n"
     "        base::EqualsCaseInsensitiveASCII(shadow_host, \"true\"))) {\n"
     "    auto rgb = [&](ui::ColorId id) {\n"
     "      const SkColor c = color_provider.GetColor(id);\n"
     "      return base::StringPrintf(\"%d,%d,%d\", SkColorGetR(c), SkColorGetG(c),\n"
     "                                SkColorGetB(c));\n"
     "    };\n"
     "    const std::string base = rgb(ui::kColorSysBase);\n"
     "    css_content->append(base::StringPrintf(\n"
     "        \"html:not(#z){--cr-card-background-color:rgba(%s,0.55);\"\n"
     "        \"--iris-glass-filter:blur(22px) saturate(150%%);\"\n"
     "        \"--iris-glass-border:1px solid rgba(%s,0.12);}\"\n"
     "        \"html:not(#z) body{background:\"\n"
     "        \"radial-gradient(60%% 60%% at 12%% 8%%,rgba(%s,0.30),transparent 70%%),\"\n"
     "        \"radial-gradient(55%% 55%% at 88%% 92%%,rgba(%s,0.26),transparent 70%%),\"\n"
     "        \"rgb(%s) fixed !important;}\",\n"
     "        base.c_str(), rgb(ui::kColorSysOnSurface).c_str(),\n"
     "        rgb(ui::kColorSysPrimary).c_str(), rgb(ui::kColorSysTertiary).c_str(),\n"
     "        base.c_str()));\n"
     "  }\n\n"
     "  std::move(callback).Run(\n",
     "Iris (B9 glass, apply-glass.sh)", "glass rules")
s = open(t).read()
for inc in ('#include "base/strings/stringprintf.h"\n', '#include "components/prefs/pref_service.h"\n'):
    if inc not in s:
        a = '#include "chrome/browser/ui/webui/theme_source.h"\n'
        if s.count(a) != 1: die(t + ": own include not found")
        s = s.replace(a, a + inc, 1); print("OK   %s : %s" % (t, inc.strip()))
open(t, "w").write(s)

# 6. cards blur what is behind them (only when glass sets the variables)
edit("chrome/browser/resources/settings/settings_page/settings_section.css",
     "  background-color: var(--cr-card-background-color);\n",
     "  background-color: var(--cr-card-background-color);\n"
     "  /* Iris (B9 glass): none unless the glass look is on. */\n"
     "  backdrop-filter: var(--iris-glass-filter, none);\n"
     "  border: var(--iris-glass-border, none);\n",
     "--iris-glass-filter", "frosted cards")
PY
echo "=== glass look (B9) complete ==="
