#!/usr/bin/env bash
# Iris — "Block more ads and trackers": a second, bigger bundled ad/tracker ruleset you can switch on in Settings
# (jegly 2026-10-08: "more adblock lists ... embedded, no network calls, update on each release"; verified against the
# 156.0.8078.11 sources). Needs apply-adblock.sh and apply-strict-pq-tls.sh first (same files, different anchors).
# Design: Chromium's subresource filter runs ONE ruleset at a time, so the two levels are two pre-built rulesets:
#   Standard (default) = EasyList + EasyPrivacy (apply-adblock.sh)
#   Extra              = Standard + StevenBlack hosts + HaGeZi Pro + AdGuard DNS filter + URLhaus hosts (this patch)
# Both ship inside the browser (grit resources, brotli) - nothing is downloaded, ever. Refresh both with
# adblock/build-ruleset.sh at each release. Setting = Local State bool "iris.adblock.extra" (default false):
#  - browser_process_impl.cc: registered; at startup the ruleset service is given the Standard or Extra ruleset; changing
#    the pref publishes the other one at once (RulesetService indexes it on a background thread, replaces the old one;
#    a different content_version is what triggers re-indexing; first time takes a few seconds).
#  - desktop: Settings -> Privacy and security (next to the other Iris toggles); allowlisted in prefs_util.cc like
#    iris.tls.strict_pq.   Android: Settings -> Privacy and security -> Iris section (LocalStatePrefs, like strict PQ).
# Limits (say so in the UI): network rules only; domain lists block requests to those hosts, not the page you navigate to;
# stricter lists can break some sites (turn it off, or allow ads for that site from the lock icon).
# PREREQUISITE: adblock/dist/{ruleset-extra.pb,version-extra.txt} from adblock/build-ruleset.sh.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven (browser_resources.grd, browser_process_impl.o, prefs_util.o,
# settings WebUI, chrome_java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
DIST="$DIR/../adblock/dist"
cd "$SRC"
for f in ruleset-extra.pb version-extra.txt LICENSE; do
  [ -s "$DIST/$f" ] || { echo "ERROR: $DIST/$f missing - run ~/Documents/iris/adblock/build-ruleset.sh first" >&2; exit 1; }
done
RES=chrome/browser/resources/iris_adblock
mkdir -p "$RES"
for f in ruleset-extra.pb version-extra.txt; do
  if cmp -s "$DIST/$f" "$RES/$f"; then echo "SKIP up to date: $RES/$f"; else cp "$DIST/$f" "$RES/$f"; echo "OK   $RES/$f"; fi
done
LIC=chrome/installer/linux/common/iris-filter-lists-LICENSE
if cmp -s "$DIST/LICENSE" "$LIC"; then echo "SKIP up to date: $LIC"; else cp "$DIST/LICENSE" "$LIC"; echo "OK   $LIC"; fi

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

PREF = "iris.adblock.extra"
LABEL = "Block more ads and trackers"
SUB = ("Adds the StevenBlack, HaGeZi Pro, AdGuard DNS and URLhaus lists to the built-in ones. They are part of Iris, "
       "nothing is downloaded. Takes effect straight away. Some sites may break; you can allow ads per site from the lock icon.")

# 1. grit resources
edit("chrome/browser/browser_resources.grd",
     '      <include name="IDR_IRIS_ADBLOCK_RULESET_VERSION" file="resources\\iris_adblock\\version.txt" type="BINDATA" />\n',
     '      <include name="IDR_IRIS_ADBLOCK_RULESET_VERSION" file="resources\\iris_adblock\\version.txt" type="BINDATA" />\n'
     '      <include name="IDR_IRIS_ADBLOCK_RULESET_EXTRA" file="resources\\iris_adblock\\ruleset-extra.pb" type="BINDATA" compress="brotli" />\n'
     '      <include name="IDR_IRIS_ADBLOCK_RULESET_EXTRA_VERSION" file="resources\\iris_adblock\\version-extra.txt" type="BINDATA" />\n',
     "IDR_IRIS_ADBLOCK_RULESET_EXTRA", "grit resources")

# 2. browser process
B = "chrome/browser/browser_process_impl.cc"
edit(B,
     "BrowserProcessImpl::BrowserProcessImpl(StartupData* startup_data)",
     "namespace {\n\n"
     "// Iris: Local State pref behind Settings -> \"Block more ads and trackers\" (apply-adblock-extra.sh).\n"
     "const char kIrisAdblockExtraPref[] = \"%s\";\n\n"
     "// Gives the ruleset service the bundled Standard or Extra ruleset. A different content_version makes it\n"
     "// re-index and publish; the same one is skipped.\n"
     "void PublishIrisAdblockRuleset(subresource_filter::RulesetService* service,\n"
     "                               bool extra) {\n"
     "  subresource_filter::UnindexedRulesetInfo info;\n"
     "  info.content_version = std::string(base::TrimWhitespaceASCII(\n"
     "      ui::ResourceBundle::GetSharedInstance().LoadDataResourceString(\n"
     "          extra ? IDR_IRIS_ADBLOCK_RULESET_EXTRA_VERSION\n"
     "                : IDR_IRIS_ADBLOCK_RULESET_VERSION),\n"
     "      base::TRIM_ALL));\n"
     "  info.resource_id =\n"
     "      extra ? IDR_IRIS_ADBLOCK_RULESET_EXTRA : IDR_IRIS_ADBLOCK_RULESET;\n"
     "  if (!info.content_version.empty()) {\n"
     "    service->IndexAndStoreAndPublishRulesetIfNeeded(info);\n"
     "  }\n"
     "}\n\n"
     "}  // namespace\n\n"
     "BrowserProcessImpl::BrowserProcessImpl(StartupData* startup_data)" % PREF,
     "kIrisAdblockExtraPref[]", "pref name + publish helper")
edit(B,
     "  subresource_filter::UnindexedRulesetInfo iris_ruleset;\n"
     "  iris_ruleset.content_version = std::string(base::TrimWhitespaceASCII(\n"
     "      ui::ResourceBundle::GetSharedInstance().LoadDataResourceString(\n"
     "          IDR_IRIS_ADBLOCK_RULESET_VERSION),\n"
     "      base::TRIM_ALL));\n"
     "  iris_ruleset.resource_id = IDR_IRIS_ADBLOCK_RULESET;\n"
     "  if (!iris_ruleset.content_version.empty()) {\n"
     "    subresource_filter_ruleset_service_->IndexAndStoreAndPublishRulesetIfNeeded(\n"
     "        iris_ruleset);\n"
     "  }\n",
     "  // Standard, or Extra when \"Block more ads and trackers\" is on (apply-adblock-extra.sh).\n"
     "  PublishIrisAdblockRuleset(subresource_filter_ruleset_service_.get(),\n"
     "                            local_state()->GetBoolean(kIrisAdblockExtraPref));\n",
     "PublishIrisAdblockRuleset(subresource_filter_ruleset_service_.get()", "startup publish")
edit(B,
     "  registry->RegisterBooleanPref(prefs::kDefaultBrowserSettingEnabled, false);\n",
     "  registry->RegisterBooleanPref(prefs::kDefaultBrowserSettingEnabled, false);\n"
     "  // Iris: off by default (Standard = EasyList + EasyPrivacy).\n"
     "  registry->RegisterBooleanPref(kIrisAdblockExtraPref, false);\n",
     "RegisterBooleanPref(kIrisAdblockExtraPref", "register pref")
edit(B,
     "  pref_change_registrar_.Init(local_state());\n",
     "  pref_change_registrar_.Init(local_state());\n"
     "  // Iris: switching \"Block more ads and trackers\" loads the other bundled ruleset right away.\n"
     "  pref_change_registrar_.Add(\n"
     "      kIrisAdblockExtraPref,\n"
     "      base::BindRepeating(\n"
     "          [](BrowserProcessImpl* self) {\n"
     "            if (self->subresource_filter_ruleset_service_) {\n"
     "              PublishIrisAdblockRuleset(\n"
     "                  self->subresource_filter_ruleset_service_.get(),\n"
     "                  self->local_state()->GetBoolean(kIrisAdblockExtraPref));\n"
     "            }\n"
     "          },\n"
     "          base::Unretained(this)));\n",
     "pref_change_registrar_.Add(\n      kIrisAdblockExtraPref", "observe pref")

# 3. desktop Settings
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[\"iris.shredding.enabled\"] = settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[\"iris.shredding.enabled\"] = settings_api::PrefType::kBoolean;\n"
     "  // Iris: Settings -> Privacy and security -> \"Block more ads and trackers\".\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % PREF,
     '"%s"' % PREF, "settings may read/write %s" % PREF)
edit("chrome/browser/resources/settings/privacy_page/privacy_page.html",
     "    <settings-toggle-button id=\"irisSearchSuggestToggle\" class=\"hr\"\n"
     "        pref-key=\"search.suggest_enabled\"\n"
     "        label=\"$i18n{searchSuggestPref}\"\n"
     "        sub-label=\"$i18n{searchSuggestPrefDesc}\">\n"
     "    </settings-toggle-button>\n",
     "    <settings-toggle-button id=\"irisSearchSuggestToggle\" class=\"hr\"\n"
     "        pref-key=\"search.suggest_enabled\"\n"
     "        label=\"$i18n{searchSuggestPref}\"\n"
     "        sub-label=\"$i18n{searchSuggestPrefDesc}\">\n"
     "    </settings-toggle-button>\n"
     "    <!-- Iris: bigger bundled ad/tracker lists (apply-adblock-extra.sh; English-only label, TODO localize) -->\n"
     "    <settings-toggle-button id=\"irisAdblockExtraToggle\" class=\"hr\"\n"
     "        pref-key=\"%s\"\n"
     "        label=\"%s\"\n"
     "        sub-label=\"%s\">\n"
     "    </settings-toggle-button>\n" % (PREF, LABEL, SUB),
     "irisAdblockExtraToggle", "Privacy page toggle")

# 4. Android Settings
edit("chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java",
     "        irisCategory.addPreference(irisStrictPqTls);\n",
     "        irisCategory.addPreference(irisStrictPqTls);\n"
     "        // Iris: \"Block more ads and trackers\" (browser-wide Local State pref; apply-adblock-extra.sh).\n"
     "        ChromeSwitchPreference irisAdblockExtra =\n"
     "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
     "        irisAdblockExtra.setKey(\"iris_adblock_extra\");\n"
     "        irisAdblockExtra.setPersistent(false);\n"
     "        irisAdblockExtra.setTitle(\"%s\");\n"
     "        irisAdblockExtra.setSummary(\n"
     "                \"%s\");\n"
     "        irisAdblockExtra.setEnabled(irisLocalState != null);\n"
     "        irisAdblockExtra.setChecked(\n"
     "                irisLocalState != null && irisLocalState.getBoolean(\"%s\"));\n"
     "        irisAdblockExtra.setOnPreferenceChangeListener(\n"
     "                (preference, newValue) -> {\n"
     "                    org.chromium.components.prefs.PrefService localState =\n"
     "                            org.chromium.chrome.browser.prefs.LocalStatePrefs.get();\n"
     "                    if (localState == null) return false;\n"
     "                    localState.setBoolean(\"%s\", (Boolean) newValue);\n"
     "                    return true;\n"
     "                });\n"
     "        irisCategory.addPreference(irisAdblockExtra);\n" % (LABEL, SUB, PREF, PREF),
     "irisAdblockExtra", "Android Iris section switch")
PY
echo "=== extra ad-block level complete ==="
