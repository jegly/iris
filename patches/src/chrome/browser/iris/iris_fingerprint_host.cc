// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_fingerprint_host.h"

#include "base/containers/span.h"
#include "base/no_destructor.h"
#include "base/numerics/byte_conversions.h"
#include "base/rand_util.h"
#include "base/values.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/iris/iris_shield_stats.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/document_service.h"
#include "content/public/browser/render_frame_host.h"
#include "crypto/sha2.h"
#include "net/base/schemeful_site.h"
#include "third_party/blink/public/mojom/iris/iris_fingerprint.mojom.h"
#include "url/gurl.h"

namespace iris {

namespace {

bool IsValidPreset(std::string_view preset) {
  return preset == "protected" || preset == "blank" || preset == "real";
}

std::string& SessionSecret() {
  static base::NoDestructor<std::string> secret(base::RandBytesAsString(32));
  return *secret;
}

uint64_t SeedFor(content::BrowserContext* context, const GURL& top) {
  const std::string material =
      SessionSecret() + "|" + net::SchemefulSite(top).Serialize() + "|" +
      (context->IsOffTheRecord() ? "otr" : "reg");
  const std::string digest = crypto::SHA256HashString(material);
  return base::U64FromLittleEndian(base::as_byte_span(digest).first<8u>());
}

class FingerprintHost final
    : public content::DocumentService<blink::mojom::IrisFingerprintHost> {
 public:
  FingerprintHost(
      content::RenderFrameHost& render_frame_host,
      mojo::PendingReceiver<blink::mojom::IrisFingerprintHost> receiver)
      : DocumentService(render_frame_host, std::move(receiver)) {}

  // blink::mojom::IrisFingerprintHost:
  void GetMode(GetModeCallback callback) override {
    content::RenderFrameHost& rfh = render_frame_host();
    const GURL top = rfh.GetOutermostMainFrame()->GetLastCommittedURL();
    content::BrowserContext* context = rfh.GetBrowserContext();
    const std::string preset = GetFingerprintReadsPreset(context, top);
    blink::mojom::IrisFingerprintMode mode =
        blink::mojom::IrisFingerprintMode::kProtected;
    if (preset == "blank") {
      mode = blink::mojom::IrisFingerprintMode::kBlank;
    } else if (preset == "real") {
      mode = blink::mojom::IrisFingerprintMode::kReal;
    }
    // Counted by the toolbar shield (apply-shield-stats.sh).
    ShieldStats::NoteFingerprintProtected(&rfh);
    std::move(callback).Run(mode, SeedFor(context, top));
  }

  void GetBlockThirdParty(GetBlockThirdPartyCallback callback) override {
    content::RenderFrameHost& rfh = render_frame_host();
    content::BrowserContext* context = rfh.GetBrowserContext();
    const GURL top = rfh.GetOutermostMainFrame()->GetLastCommittedURL();
    bool block = false;
    if (Profile* profile = Profile::FromBrowserContext(context)) {
      block = profile->GetPrefs()->GetBoolean("iris.privacy.block_third_party");
    }
    // One site can be exempted with "Allow ads" from the lock icon.
    if (block) {
      HostContentSettingsMap* map =
          HostContentSettingsMapFactory::GetForProfile(context);
      if (map && map->GetContentSetting(top, top, ContentSettingsType::ADS) ==
                     CONTENT_SETTING_ALLOW) {
        block = false;
      }
    }
    std::move(callback).Run(block);
  }
};

}  // namespace

void BindFingerprintHost(
    content::RenderFrameHost* render_frame_host,
    mojo::PendingReceiver<blink::mojom::IrisFingerprintHost> receiver) {
  // Owned by the document (DocumentService deletes itself).
  new FingerprintHost(*render_frame_host, std::move(receiver));
}

namespace {

// Website-setting values must be dictionaries (content_settings_pref.cc
// IsValueAllowedForType): stored as {"preset": "<id>"}. The plain string that
// 156.0.8073.0-1 stored is still read.
std::string PresetFromSettingValue(const base::Value& value) {
  if (value.is_string()) {
    return value.GetString();
  }
  if (const base::DictValue* dict = value.GetIfDict()) {
    if (const std::string* preset = dict->FindString("preset")) {
      return *preset;
    }
  }
  return std::string();
}

base::Value PresetToSettingValue(std::string_view preset) {
  base::DictValue dict;
  dict.Set("preset", preset);
  return base::Value(std::move(dict));
}

}  // namespace

void RerollFingerprintSeed() {
  SessionSecret() = base::RandBytesAsString(32);
}

std::string GetFingerprintReadsPreset(content::BrowserContext* context,
                                      const GURL& url) {
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(context);
  if (!map || !url.SchemeIsHTTPOrHTTPS()) {
    return "protected";
  }
  const base::Value value = map->GetWebsiteSetting(
      url, url, ContentSettingsType::IRIS_FINGERPRINT_READS);
  const std::string preset = PresetFromSettingValue(value);
  return IsValidPreset(preset) ? preset : "protected";
}

void SetFingerprintReadsPreset(content::BrowserContext* context,
                               const GURL& url,
                               std::string_view preset) {
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(context);
  if (!map || !url.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  // "protected" is the default: store nothing.
  map->SetWebsiteSettingDefaultScope(
      url, GURL(), ContentSettingsType::IRIS_FINGERPRINT_READS,
      (preset == "blank" || preset == "real") ? PresetToSettingValue(preset)
                                              : base::Value());
}

}  // namespace iris
