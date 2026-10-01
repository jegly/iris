// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/ui/webui/version/iris_protections.h"

#include <string>
#include <string_view>
#include <vector>

#include "base/cfi_buildflags.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "build/build_config.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/chrome_features.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/pref_names.h"
#include "components/content_settings/core/browser/cookie_settings.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/content_settings/core/common/pref_names.h"
#include "components/lens/lens_features.h"
#include "components/network_time/network_time_tracker.h"
#include "components/omnibox/browser/aim_eligibility_service_features.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/site_isolation_policy.h"
#include "content/public/common/content_switches.h"
#include "gpu/config/gpu_finch_features.h"
#include "third_party/blink/public/common/global_privacy_control/global_privacy_control_util.h"

namespace iris {

namespace {

void Line(std::string& out,
          std::string_view name,
          bool on,
          std::string_view detail) {
  base::StrAppend(&out, {on ? "✓ " : "✗ ", name, ": ", detail, "\n"});
}

std::string BuiltInHardening() {
  std::vector<std::string_view> items;
#if BUILDFLAG(CFI_ICALL_CHECK)
  items.push_back("CFI");
#endif
#if defined(__has_feature)
#if __has_feature(shadow_call_stack)
  items.push_back("shadow call stack");
#endif
#endif
#if defined(__ARM_FEATURE_PAC_DEFAULT) && defined(__ARM_FEATURE_BTI_DEFAULT)
  items.push_back("ARM PAC + BTI");
#endif
#if defined(__SSP_STRONG__)
  items.push_back("strong stack protector");
#endif
#if defined(_FORTIFY_SOURCE) && _FORTIFY_SOURCE >= 3
  items.push_back("FORTIFY_SOURCE=3");
#elif defined(_FORTIFY_SOURCE) && _FORTIFY_SOURCE == 2
  items.push_back("FORTIFY_SOURCE=2");
#endif
#if defined(_LIBCPP_HARDENING_MODE) && defined(_LIBCPP_HARDENING_MODE_EXTENSIVE) && \
    _LIBCPP_HARDENING_MODE == _LIBCPP_HARDENING_MODE_EXTENSIVE
  items.push_back("hardened libc++");
#endif
  return base::JoinString(items, ", ");
}

}  // namespace

std::string ProtectionsReport(Profile* profile) {
  std::string out;
  const base::CommandLine& cl = *base::CommandLine::ForCurrentProcess();
  PrefService* prefs = profile->GetPrefs();
  PrefService* local_state = g_browser_process->local_state();

  // Process isolation.
  const bool all_sites =
      content::SiteIsolationPolicy::UseDedicatedProcessesForAllSites();
  Line(out, "Site isolation", all_sites,
       all_sites ? "every site in its own process" : "partial");
  const bool strict_origin =
      content::SiteIsolationPolicy::IsStrictOriginIsolationEnabled();
  Line(out, "Origin isolation", strict_origin, strict_origin ? "strict" : "off");

  // JavaScript engine.
  const ContentSetting jit =
      HostContentSettingsMapFactory::GetForProfile(profile)
          ->GetDefaultContentSetting(ContentSettingsType::JAVASCRIPT_JIT);
  Line(out, "JavaScript JIT for websites", jit == CONTENT_SETTING_BLOCK,
       jit == CONTENT_SETTING_BLOCK ? "off (no WebAssembly)" : "on");

  // Network.
  const std::string doh_mode = local_state->GetString(prefs::kDnsOverHttpsMode);
  const std::string doh_server =
      local_state->GetString(prefs::kDnsOverHttpsTemplates);
  Line(out, "Encrypted DNS", doh_mode == "secure",
       doh_server.empty() ? doh_mode
                          : base::StrCat({doh_mode, " (", doh_server, ")"}));
  const bool https_only = prefs->GetBoolean(prefs::kHttpsOnlyModeEnabled);
  Line(out, "HTTPS-Only", https_only, https_only ? "on" : "off");
  const bool block_3p =
      prefs->GetInteger(prefs::kCookieControlsMode) ==
      static_cast<int>(content_settings::CookieControlsMode::kBlockThirdParty);
  Line(out, "Third-party cookies", block_3p, block_3p ? "blocked" : "allowed");
  const bool gpc = blink::IsGlobalPrivacyControlFeatureEnabled();
  Line(out, "Global Privacy Control", gpc, gpc ? "sent to every site" : "off");

  // Web platform.
  const std::string blocked_apis =
      cl.GetSwitchValueASCII(switches::kDisableBlinkFeatures);
  const size_t blocked_count =
      blocked_apis.empty()
          ? 0
          : base::SplitString(blocked_apis, ",", base::TRIM_WHITESPACE,
                              base::SPLIT_WANT_NONEMPTY)
                .size();
  Line(out, "Risky web APIs", blocked_count > 0,
       base::StrCat({base::NumberToString(blocked_count),
                     " off (listed under Command Line)"}));
  const bool webgpu = base::FeatureList::IsEnabled(features::kWebGPUService);
  Line(out, "WebGPU", !webgpu, webgpu ? "on" : "off");

  // Google and AI.
  const bool bg_net = cl.HasSwitch(switches::kDisableBackgroundNetworking);
  Line(out, "Background networking", bg_net, bg_net ? "off" : "on");
  const bool net_time =
      base::FeatureList::IsEnabled(network_time::kNetworkTimeServiceQuerying);
  Line(out, "Google network time", !net_time,
       net_time ? "on" : "off (system clock)");
  const bool glic = base::FeatureList::IsEnabled(features::kGlic);
  Line(out, "Gemini", !glic, glic ? "on" : "off");
  const bool aim = base::FeatureList::IsEnabled(omnibox::kAimEnabled);
  Line(out, "AI Mode", !aim, aim ? "on" : "off");
  const bool lens = base::FeatureList::IsEnabled(lens::features::kLensOverlay);
  Line(out, "Google Lens", !lens, lens ? "on" : "off");

  base::StrAppend(&out, {"Built in: component updates limited to CRLSet + "
                         "certificate data; ",
                         BuiltInHardening()});
  return out;
}

}  // namespace iris
