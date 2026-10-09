// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "chrome/browser/iris/iris_shield_stats.h"

#include "base/time/time.h"
#include "components/content_settings/browser/page_specific_content_settings.h"
#include "components/subresource_filter/content/browser/content_subresource_filter_throttle_manager.h"
#include "components/subresource_filter/content/browser/page_load_statistics.h"
#include "content/public/browser/page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "net/base/schemeful_site.h"

namespace iris {

namespace {
// The renderers' ad statistics arrive around the end of the load: look again shortly after.
constexpr base::TimeDelta kRefreshDelay = base::Seconds(2);
}  // namespace

ShieldStats::ShieldStats(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<ShieldStats>(*web_contents) {}

ShieldStats::~ShieldStats() = default;

int ShieldStats::ads() const {
  if (!web_contents()) {
    return 0;
  }
  subresource_filter::ContentSubresourceFilterThrottleManager* manager =
      subresource_filter::ContentSubresourceFilterThrottleManager::FromPage(
          web_contents()->GetPrimaryPage());
  if (!manager) {
    return 0;
  }
  subresource_filter::PageLoadStatistics* statistics =
      manager->page_load_statistics();
  return statistics ? statistics->num_loads_disallowed() : 0;
}

int ShieldStats::cookies() const {
  if (!web_contents()) {
    return 0;
  }
  content_settings::PageSpecificContentSettings* settings =
      content_settings::PageSpecificContentSettings::GetForFrame(
          web_contents()->GetPrimaryMainFrame());
  return settings ? settings->GetBlockedCookieCount() : 0;
}

void ShieldStats::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ShieldStats::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

// static
void ShieldStats::NoteFingerprintProtected(content::RenderFrameHost* rfh) {
  if (!rfh) {
    return;
  }
  content::WebContents* web_contents =
      content::WebContents::FromRenderFrameHost(rfh);
  ShieldStats* stats = web_contents ? FromWebContents(web_contents) : nullptr;
  if (!stats) {
    return;
  }
  const std::string site =
      net::SchemefulSite(rfh->GetLastCommittedOrigin()).Serialize();
  if (stats->fingerprint_sites_.insert(site).second) {
    stats->NotifyChanged();
  }
}

void ShieldStats::PrimaryPageChanged(content::Page& page) {
  fingerprint_sites_.clear();
  refresh_timer_.Stop();
  NotifyChanged();
}

void ShieldStats::DidFinishLoad(content::RenderFrameHost* render_frame_host,
                                const GURL& validated_url) {
  if (!render_frame_host->IsInPrimaryMainFrame()) {
    return;
  }
  NotifyChanged();
  refresh_timer_.Start(FROM_HERE, kRefreshDelay,
                       base::BindOnce(&ShieldStats::NotifyChanged,
                                      base::Unretained(this)));
}

void ShieldStats::NotifyChanged() {
  for (Observer& observer : observers_) {
    observer.OnShieldStatsChanged();
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(ShieldStats);

}  // namespace iris
