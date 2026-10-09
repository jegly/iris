// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: what the toolbar shield counts for the current page (apply-shield-stats.sh).
//   ads/trackers  requests the ad blocker (subresource filter) refused on this page, all frames. Chromium's renderers
//                 send one statistics message per document when it finishes loading; PageLoadStatistics sums them.
//   cookies       distinct cookies whose access was blocked on this page (PageSpecificContentSettings).
//   fingerprints  documents (distinct sites) whose canvas/audio reading Iris protected or blanked: reported by
//                 IrisFingerprintHost the first time a document's protected API is used.
// The numbers belong to the primary page; they reset when it changes. Observers hear about every change (the ad
// total only arrives after the load finishes, so a refresh is also scheduled shortly after load).

#ifndef CHROME_BROWSER_IRIS_IRIS_SHIELD_STATS_H_
#define CHROME_BROWSER_IRIS_IRIS_SHIELD_STATS_H_

#include <set>
#include <string>

#include "base/observer_list.h"
#include "base/observer_list_types.h"
#include "base/timer/timer.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

namespace content {
class RenderFrameHost;
}

namespace iris {

class ShieldStats : public content::WebContentsObserver,
                    public content::WebContentsUserData<ShieldStats> {
 public:
  class Observer : public base::CheckedObserver {
   public:
    virtual void OnShieldStatsChanged() = 0;
  };

  ShieldStats(const ShieldStats&) = delete;
  ShieldStats& operator=(const ShieldStats&) = delete;
  ~ShieldStats() override;

  int ads() const;
  int cookies() const;
  int fingerprints() const { return static_cast<int>(fingerprint_sites_.size()); }
  int total() const { return ads() + cookies() + fingerprints(); }
  // Everything the shield has counted in this profile since it was created.
  int lifetime() const;

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

  // Called by IrisFingerprintHost when a document first reads canvas/audio data.
  static void NoteFingerprintProtected(content::RenderFrameHost* rfh);

  // content::WebContentsObserver:
  void PrimaryPageChanged(content::Page& page) override;
  void DidFinishLoad(content::RenderFrameHost* render_frame_host,
                     const GURL& validated_url) override;

 private:
  friend class content::WebContentsUserData<ShieldStats>;
  explicit ShieldStats(content::WebContents* web_contents);

  void NotifyChanged();

  std::set<std::string> fingerprint_sites_;
  int counted_ = 0;  // part of total() already added to the lifetime count
  base::OneShotTimer refresh_timer_;
  base::ObserverList<Observer> observers_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace iris

#endif  // CHROME_BROWSER_IRIS_IRIS_SHIELD_STATS_H_
