#!/usr/bin/env bash
# Iris — built-in ad/tracker blocking with Chromium's own Subresource Filter (approved by jegly 2026-09-26;
# verified against checkout 2026-09-26). Cromite/Trivalent approach, own code. NOT Brave (never built).
#
# PREREQUISITE: ~/Documents/iris/adblock/dist/{ruleset.pb,version.txt} produced by adblock/build-ruleset.sh
# (EasyList + EasyPrivacy -> Chromium "unindexed ruleset" via //components/subresource_filter/tools:ruleset_converter).
# This script refuses to run without them (the .grd would otherwise reference missing files).
#
# WHAT IT CHANGES (all verified):
# 1. Rules ship INSIDE the browser as grit resources (chrome/browser/browser_resources.grd, unconditional ->
#    Linux + Android, no packaging changes): IDR_IRIS_ADBLOCK_RULESET (brotli) + IDR_IRIS_ADBLOCK_RULESET_VERSION.
#    UnindexedRulesetInfo.resource_id is an upstream-supported source (ruleset_version.h); it is read with
#    ResourceBundle::LoadDataResourceString (decompresses) in unindexed_ruleset_stream_generator.cc.
# 2. Load at startup: chrome/browser/browser_process_impl.cc CreateSubresourceFilterRulesetService() -> right after
#    RulesetService::Create(): IndexAndStoreAndPublishRulesetIfNeeded({resource_id, content_version}).
#    Runs on both platforms, independent of the component updater. RulesetService queues it until initialised and
#    SKIPS re-indexing when content_version equals the last indexed one (ruleset_service.cc) -> cheap on restart.
# 3. The Google "Subresource Filter Rules" component is no longer registered
#    (chrome/browser/component_updater/subresource_filter_component_installer.cc) — Iris bundles its own list and
#    must not have it replaced by a Google-delivered one (or ping for it).
# 4. Activation on ALL sites: components/subresource_filter/core/browser/subresource_filter_features.cc gets a new
#    default-enabled preset "iris_liverun_on_all_sites" = Configuration(kEnabled, ALL_SITES), priority 1100 (above
#    phishing 1000 / better-ads 800). SafeBrowsingPageActivationThrottle::DoesRootFrameURLSatisfyActivationConditions
#    returns true for ALL_SITES without any list match. Per-site "Allow ads" still wins
#    (ProfileInteractionManager::OnPageActivationComputed -> GetSitePermission(ADS) == ALLOW -> URL_ALLOWLISTED);
#    ContentSettingsType::ADS is already default BLOCK upstream.
# 5. PRIVACY: upstream writes per-site ADS_DATA metadata on EVERY activation computation
#    (profile_interaction_manager.cc SetSiteMetadataBasedOnActivation, 7-day expiry). With ALL_SITES that would be a
#    rolling 7-day list of every visited site in Preferences, outside History. Iris skips that write.
#    Consequence handled: Page Info shows the "Ads" row only if GetSiteActivationFromMetadata() is true
#    (page_info.cc) -> it now returns true (Iris filters everywhere), so the per-site toggle stays available.
#    Still written (upstream, unchanged): the "last shown" timestamp when the ads-blocked UI is shown on a site
#    (smart-UI rate limit; only for sites where something was actually blocked).
# NOT CHANGED: Android navigation-time Safe Browsing check (RemoteSafeBrowsingDatabaseManager) — the throttle
#   already runs on every navigation upstream for the phishing/better-ads presets; ALL_SITES adds no new request.
#   Runtime-verify: no navigation delay.
# LIMITS: network-level URL rules only (no cosmetic/element-hiding rules; the converter drops unsupported syntax).
# 6. ATTRIBUTION (EasyList/EasyPrivacy: GPLv3+ / CC BY-SA 3.0): adblock/dist/LICENSE ships in the .deb as
#    /usr/share/doc/<package>/filter-lists-LICENSE (chrome/installer/linux: file in common/, added to the gn
#    common_packaging_files copy, copied into the doc dir by debian/build.py after stage_install_common()).
# Guarded; idempotent (markers); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
DIST="$DIR/../adblock/dist"
cd "$SRC"
for f in ruleset.pb version.txt LICENSE; do
  [ -s "$DIST/$f" ] || { echo "ERROR: $DIST/$f missing — run ~/Documents/iris/adblock/build-ruleset.sh first" >&2; exit 1; }
done

# --- data files into the tree (always refreshed; re-running with a new list = new version.txt) ---
RES=chrome/browser/resources/iris_adblock
mkdir -p "$RES"
for f in ruleset.pb version.txt; do
  if cmp -s "$DIST/$f" "$RES/$f"; then echo "SKIP up to date: $RES/$f"; else cp "$DIST/$f" "$RES/$f"; echo "OK   $RES/$f"; fi
done
LIC=chrome/installer/linux/common/iris-filter-lists-LICENSE
if cmp -s "$DIST/LICENSE" "$LIC"; then echo "SKIP up to date: $LIC"; else cp "$DIST/LICENSE" "$LIC"; echo "OK   $LIC"; fi

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: " + path + " (" + marker[:40] + ")"); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:70]!r}")
    open(path, "w").write(s.replace(old, new, 1)); print("OK   " + path)

# 1) grit resources (unconditional, last entries of <includes>)
edit("chrome/browser/browser_resources.grd",
     "        <part file=\"ui/views/webid/resources/webid_resources.grdp\" />\n      </if>\n    </includes>",
     "        <part file=\"ui/views/webid/resources/webid_resources.grdp\" />\n      </if>\n"
     "      <!-- Iris: bundled ad/tracker filter rules (EasyList + EasyPrivacy), see browser_process_impl.cc. -->\n"
     "      <include name=\"IDR_IRIS_ADBLOCK_RULESET\" file=\"resources\\iris_adblock\\ruleset.pb\" type=\"BINDATA\" compress=\"brotli\" />\n"
     "      <include name=\"IDR_IRIS_ADBLOCK_RULESET_VERSION\" file=\"resources\\iris_adblock\\version.txt\" type=\"BINDATA\" />\n"
     "    </includes>",
     "IDR_IRIS_ADBLOCK_RULESET")

# 2) publish at startup
B = "chrome/browser/browser_process_impl.cc"
edit(B,
     '#include "components/subresource_filter/content/browser/ruleset_service.h"\n',
     '#include "components/subresource_filter/content/browser/ruleset_service.h"\n'
     '#include "chrome/grit/browser_resources.h"  // Iris: IDR_IRIS_ADBLOCK_RULESET\n'
     '#include "ui/base/resource/resource_bundle.h"  // Iris\n',
     "IDR_IRIS_ADBLOCK_RULESET\n")
edit(B,
     "          subresource_filter::SafeBrowsingRulesetPublisher::Factory());\n}\n",
     "          subresource_filter::SafeBrowsingRulesetPublisher::Factory());\n\n"
     "  // Iris: publish the bundled ad/tracker filter rules (EasyList + EasyPrivacy)\n"
     "  // from resources.pak. RulesetService queues this until it is initialized\n"
     "  // and skips re-indexing when this content_version is already indexed.\n"
     "  subresource_filter::UnindexedRulesetInfo iris_ruleset;\n"
     "  iris_ruleset.content_version = std::string(base::TrimWhitespaceASCII(\n"
     "      ui::ResourceBundle::GetSharedInstance().LoadDataResourceString(\n"
     "          IDR_IRIS_ADBLOCK_RULESET_VERSION),\n"
     "      base::TRIM_ALL));\n"
     "  iris_ruleset.resource_id = IDR_IRIS_ADBLOCK_RULESET;\n"
     "  if (!iris_ruleset.content_version.empty()) {\n"
     "    subresource_filter_ruleset_service_->IndexAndStoreAndPublishRulesetIfNeeded(\n"
     "        iris_ruleset);\n"
     "  }\n}\n",
     "iris_ruleset.resource_id = IDR_IRIS_ADBLOCK_RULESET;")
s = open(B).read()
if '#include "base/strings/string_util.h"' not in s:
    edit(B, '#include "chrome/grit/browser_resources.h"  // Iris: IDR_IRIS_ADBLOCK_RULESET\n',
            '#include "chrome/grit/browser_resources.h"  // Iris: IDR_IRIS_ADBLOCK_RULESET\n'
            '#include "base/strings/string_util.h"  // Iris\n', '#include "base/strings/string_util.h"  // Iris')

# 3) no Google ruleset component (whole body replaced; no dead code -> -Wunreachable-code-aggressive safe)
edit("chrome/browser/component_updater/subresource_filter_component_installer.cc",
     "void RegisterSubresourceFilterComponent(ComponentUpdateService* cus) {\n"
     "  if (!base::FeatureList::IsEnabled(\n"
     "          subresource_filter::kSafeBrowsingSubresourceFilter)) {\n"
     "    return;\n"
     "  }\n"
     "\n"
     "  auto installer = base::MakeRefCounted<ComponentInstaller>(\n"
     "      std::make_unique<SubresourceFilterComponentInstallerPolicy>());\n"
     "  installer->Register(cus, base::OnceClosure());\n"
     "}\n",
     "void RegisterSubresourceFilterComponent(ComponentUpdateService* cus) {\n"
     "  // Iris: the ruleset is bundled (browser_process_impl.cc); never fetch or\n"
     "  // replace it with the Google-delivered component.\n"
     "}\n",
     "// Iris: the ruleset is bundled")

# 4) ALL_SITES live-run preset, enabled by default
F = "components/subresource_filter/core/browser/subresource_filter_features.cc"
edit(F,
     "std::vector<Configuration> FillEnabledPresetConfigurations(\n",
     "// Iris: filter ads/trackers on all sites with the bundled ruleset.\n"
     "constexpr char kPresetIrisLiveRunOnAllSites[] = \"iris_liverun_on_all_sites\";\n"
     "Configuration MakePresetForIrisLiveRunOnAllSites() {\n"
     "  Configuration config(mojom::ActivationLevel::kEnabled,\n"
     "                       ActivationScope::ALL_SITES);\n"
     "  config.activation_conditions.priority = 1100;\n"
     "  return config;\n"
     "}\n\n"
     "std::vector<Configuration> FillEnabledPresetConfigurations(\n",
     "kPresetIrisLiveRunOnAllSites[]")
edit(F,
     "      {kPresetLiveRunForBetterAds, true,\n       &Configuration::MakePresetForLiveRunForBetterAds}};",
     "      {kPresetLiveRunForBetterAds, true,\n       &Configuration::MakePresetForLiveRunForBetterAds},\n"
     "      {kPresetIrisLiveRunOnAllSites, true,\n       &MakePresetForIrisLiveRunOnAllSites}};",
     "&MakePresetForIrisLiveRunOnAllSites}")

# 5) privacy: no per-visit ADS_DATA record; Page Info keeps the Ads toggle
P = "components/subresource_filter/content/browser/profile_interaction_manager.cc"
edit(P,
     "  const GURL& url(navigation_handle->GetURL());\n"
     "  if (url.SchemeIsHTTPOrHTTPS()) {\n"
     "    profile_context_->settings_manager()->SetSiteMetadataBasedOnActivation(\n"
     "        url, effective_activation_level == mojom::ActivationLevel::kEnabled,\n"
     "        SubresourceFilterContentSettingsManager::ActivationSource::\n"
     "            kSafeBrowsing);\n"
     "  }\n",
     "  const GURL& url(navigation_handle->GetURL());\n"
     "  // Iris: filtering is active on every site, so per-site activation metadata\n"
     "  // (SetSiteMetadataBasedOnActivation) would only keep a 7-day list of\n"
     "  // visited sites. Not written.\n",
     "// Iris: filtering is active on every site")
C = "components/subresource_filter/content/browser/subresource_filter_content_settings_manager.cc"
edit(C,
     "bool SubresourceFilterContentSettingsManager::GetSiteActivationFromMetadata(\n"
     "    const GURL& url) {\n"
     "  std::optional<base::DictValue> dict = GetSiteMetadata(url);\n"
     "\n"
     "  // If there is no dict, this is metadata V1, absence of metadata\n"
     "  // implies no activation.\n"
     "  if (!dict) {\n"
     "    return false;\n"
     "  }\n"
     "\n"
     "  std::optional<bool> site_activation_status = dict->FindBool(kActivatedKey);\n"
     "\n"
     "  // If there is no explicit site activation status, it is metadata V1:\n"
     "  // use the presence of metadata as indicative of the site activation.\n"
     "  // Otherwise it is metadata V2, we return the activation stored in\n"
     "  // kActivatedKey.\n"
     "  return !site_activation_status || *site_activation_status;\n"
     "}\n",
     "bool SubresourceFilterContentSettingsManager::GetSiteActivationFromMetadata(\n"
     "    const GURL& url) {\n"
     "  // Iris: the filter is active on all sites (per-visit metadata is not\n"
     "  // stored), so every site counts as activated; keeps Page Info's Ads toggle.\n"
     "  return true;\n"
     "}\n",
     "// Iris: the filter is active on all sites")
# 6) attribution in the .deb
edit("chrome/installer/linux/BUILD.gn",
     '    "common/wrapper",\n  ]\n\n  if (is_chrome_branded) {\n    sources += [ "common/google-chrome.info" ]',
     '    "common/wrapper",\n    "common/iris-filter-lists-LICENSE",  # Iris: EasyList/EasyPrivacy attribution\n  ]\n\n'
     '  if (is_chrome_branded) {\n    sources += [ "common/google-chrome.info" ]',
     "common/iris-filter-lists-LICENSE")
edit("chrome/installer/linux/debian/build.py",
     "        inst.stage_install_common()\n\n        logging.info(f\"Staging Debian install files in '{staging_dir}'...\")\n",
     "        inst.stage_install_common()\n\n"
     "        # Iris: attribution for the bundled EasyList/EasyPrivacy filter rules.\n"
     "        shutil.copy(\n"
     "            output_dir / \"installer/common/iris-filter-lists-LICENSE\",\n"
     "            staging_dir\n"
     "            / f\"usr/share/doc/{config.usr_bin_symlink_name}/filter-lists-LICENSE\",\n"
     "        )\n\n"
     "        logging.info(f\"Staging Debian install files in '{staging_dir}'...\")\n",
     "iris-filter-lists-LICENSE")
PY
echo "=== ad blocking (subresource filter, bundled lists) complete ==="
