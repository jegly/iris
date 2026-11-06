#!/usr/bin/env bash
# Iris — "Block the most ads, trackers and threats": a third bundled ad-block level, OFF by default (issue #2 by
# ziya333-art; jegly 2026-11-05: "medium ... toggles like the other block lists ... off by default").
# STATIC, like Standard and "Block more" (jegly 2026-11-05: "they need to be static ... not phoning for updates"):
# adblock/build-ruleset.sh builds dist/ruleset-max.pb on the build machine; it ships inside Iris (grit, brotli) and
# changes only with a release. Nothing is downloaded or checked at runtime.
# Contents: Standard + the Block-more lists with HaGeZi Pro replaced by HaGeZi Ultimate (superset of Pro), plus HaGeZi
# Threat Intelligence Feeds (medium) and HaGeZi Fake. Chromium's filter runs one ruleset, so Max is a superset.
# Setting = Local State bool "iris.adblock.max". browser_process_impl.cc: PublishIrisAdblockRuleset() picks the
# highest level that is on (Max > Block more > Standard), at start and whenever either pref changes.
# UI: desktop Settings -> Privacy and security -> Iris hardening -> Ads and trackers, under "Block more"; Android
# Settings -> Privacy and security -> Ads and trackers (LocalStatePrefs, like "Block more"). English-only labels.
# Needs apply-adblock-extra, apply-iris-hardening-page (anchors) and adblock/dist/{ruleset-max.pb,version-max.txt}.
# STATUS 2026-11-05: copy-tested on 157 copies, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
DIST="$DIR/../adblock/dist"
cd "$SRC"
for f in ruleset-max.pb version-max.txt; do
  [ -s "$DIST/$f" ] || { echo "ERROR: $DIST/$f missing - run ~/Documents/iris/adblock/build-ruleset.sh first" >&2; exit 1; }
done
RES=chrome/browser/resources/iris_adblock
mkdir -p "$RES"
for f in ruleset-max.pb version-max.txt; do
  if cmp -s "$DIST/$f" "$RES/$f"; then echo "SKIP up to date: $RES/$f"; else cp "$DIST/$f" "$RES/$f"; echo "OK   $RES/$f"; fi
done
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
PREF = "iris.adblock.max"
LABEL = "Block the most ads, trackers and threats"
SUB = ("Adds HaGeZi Ultimate, Threat Intelligence Feeds (medium) and Fake to the lists above. They are part of Iris, "
       "nothing is downloaded; they change only with each Iris release. Blocks the most and breaks the most sites; you "
       "can allow ads per site from the lock icon.")

# 1. grit resources
a = ('      <include name="IDR_IRIS_ADBLOCK_RULESET_EXTRA_VERSION" file="resources\\iris_adblock\\version-extra.txt" '
     'type="BINDATA" />\n')
edit("chrome/browser/browser_resources.grd", a,
     a + '      <include name="IDR_IRIS_ADBLOCK_RULESET_MAX" file="resources\\iris_adblock\\ruleset-max.pb" type="BINDATA" compress="brotli" />\n'
         '      <include name="IDR_IRIS_ADBLOCK_RULESET_MAX_VERSION" file="resources\\iris_adblock\\version-max.txt" type="BINDATA" />\n',
     "IDR_IRIS_ADBLOCK_RULESET_MAX", "grit resources")

# 2. browser process. The Max check sits at the top of PublishIrisAdblockRuleset() (apply-adblock-extra.sh's helper),
#    so every existing caller (startup, the Block-more observer) picks Max when it is on; apply-adblock-extra's own lines
#    stay untouched. One more observer re-publishes when Max is switched.
B = "chrome/browser/browser_process_impl.cc"
edit(B, "// Gives the ruleset service the bundled Standard or Extra ruleset. A different content_version makes it\n",
     "// Iris: Local State pref behind \"Block the most ads, trackers and threats\" (apply-adblock-max.sh).\n"
     "const char kIrisAdblockMaxPref[] = \"%s\";\n\n"
     "// Gives the ruleset service the bundled Standard or Extra ruleset. A different content_version makes it\n" % PREF,
     "kIrisAdblockMaxPref[]", "pref name")
edit(B, "void PublishIrisAdblockRuleset(subresource_filter::RulesetService* service,\n"
        "                               bool extra) {\n"
        "  subresource_filter::UnindexedRulesetInfo info;\n",
     "void PublishIrisAdblockRuleset(subresource_filter::RulesetService* service,\n"
     "                               bool extra) {\n"
     "  // Iris (apply-adblock-max.sh): the Max level wins over Block more / Standard.\n"
     "  PrefService* iris_local_state =\n"
     "      g_browser_process ? g_browser_process->local_state() : nullptr;\n"
     "  if (iris_local_state && iris_local_state->GetBoolean(kIrisAdblockMaxPref)) {\n"
     "    subresource_filter::UnindexedRulesetInfo max_info;\n"
     "    max_info.content_version = std::string(base::TrimWhitespaceASCII(\n"
     "        ui::ResourceBundle::GetSharedInstance().LoadDataResourceString(\n"
     "            IDR_IRIS_ADBLOCK_RULESET_MAX_VERSION),\n"
     "        base::TRIM_ALL));\n"
     "    max_info.resource_id = IDR_IRIS_ADBLOCK_RULESET_MAX;\n"
     "    if (!max_info.content_version.empty()) {\n"
     "      service->IndexAndStoreAndPublishRulesetIfNeeded(max_info);\n"
     "      return;\n"
     "    }\n"
     "  }\n"
     "  subresource_filter::UnindexedRulesetInfo info;\n",
     "the Max level wins over Block more", "Max wins")
edit(B, "#if BUILDFLAG(IS_ANDROID)\n  chrome_browser_prefs::OnLocalStatePrefsLoaded();\n",
     "  // Iris: \"Block the most ads, trackers and threats\" (apply-adblock-max.sh).\n"
     "  pref_change_registrar_.Add(\n"
     "      kIrisAdblockMaxPref,\n"
     "      base::BindRepeating(\n"
     "          [](BrowserProcessImpl* self) {\n"
     "            if (self->subresource_filter_ruleset_service_) {\n"
     "              PublishIrisAdblockRuleset(\n"
     "                  self->subresource_filter_ruleset_service_.get(),\n"
     "                  self->local_state()->GetBoolean(kIrisAdblockExtraPref));\n"
     "            }\n"
     "          },\n"
     "          base::Unretained(this)));\n\n"
     "#if BUILDFLAG(IS_ANDROID)\n  chrome_browser_prefs::OnLocalStatePrefsLoaded();\n",
     "      kIrisAdblockMaxPref,\n", "observe Max")
edit(B, "  registry->RegisterBooleanPref(kIrisAdblockExtraPref, false);\n",
     "  registry->RegisterBooleanPref(kIrisAdblockExtraPref, false);\n"
     "  registry->RegisterBooleanPref(kIrisAdblockMaxPref, false);  // Iris: off\n",
     "RegisterBooleanPref(kIrisAdblockMaxPref", "register pref")

# 3. desktop Settings
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % PREF,
     "\"%s\"" % PREF, "allowlist")
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
s = open(H).read()
i = s.find('    <settings-toggle-button id="irisAdblockExtraToggle"')
if "irisAdblockMaxToggle" in s:
    print("SKIP already applied: %s (desktop toggle)" % H)
elif i < 0 or s.count('id="irisAdblockExtraToggle"') != 1:
    die("%s: Block-more toggle not found exactly once (drift?)" % H)
else:
    j = s.find("    </settings-toggle-button>\n", i) + len("    </settings-toggle-button>\n")
    tog = ("    <settings-toggle-button id=\"irisAdblockMaxToggle\" class=\"hr\"\n"
           "        pref-key=\"%s\"\n"
           "        label=\"%s\"\n"
           "        sub-label=\"%s\">\n"
           "    </settings-toggle-button>\n" % (PREF, LABEL, SUB))
    open(H, "w").write(s[:j] + tog + s[j:]); print("OK   %s : desktop toggle" % H)

# 4. Android: switch next to "Block more", grouped under "Ads and trackers"
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
edit(J, "        irisCategory.addPreference(irisAdblockExtra);\n",
     "        irisCategory.addPreference(irisAdblockExtra);\n"
     "        // Iris: \"Block the most ads, trackers and threats\" (Local State; apply-adblock-max.sh).\n"
     "        ChromeSwitchPreference irisAdblockMax =\n"
     "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
     "        irisAdblockMax.setKey(\"iris_adblock_max\");\n"
     "        irisAdblockMax.setPersistent(false);\n"
     "        irisAdblockMax.setTitle(\"%s\");\n"
     "        irisAdblockMax.setSummary(\n"
     "                \"%s\");\n"
     "        irisAdblockMax.setEnabled(irisLocalState != null);\n"
     "        irisAdblockMax.setChecked(\n"
     "                irisLocalState != null && irisLocalState.getBoolean(\"%s\"));\n"
     "        irisAdblockMax.setOnPreferenceChangeListener(\n"
     "                (preference, newValue) -> {\n"
     "                    org.chromium.components.prefs.PrefService localState =\n"
     "                            org.chromium.chrome.browser.prefs.LocalStatePrefs.get();\n"
     "                    if (localState == null) return false;\n"
     "                    localState.setBoolean(\"%s\", (Boolean) newValue);\n"
     "                    return true;\n"
     "                });\n"
     "        irisCategory.addPreference(irisAdblockMax);\n" % (LABEL, SUB, PREF, PREF),
     "irisAdblockMax", "Android switch")
edit(J, '"iris_block_ads", "iris_adblock_extra", ',
     '"iris_block_ads", "iris_adblock_extra", "iris_adblock_max", ',
     '"iris_adblock_max", ', "Android group")
PY
echo "=== max ad-block level complete ==="
