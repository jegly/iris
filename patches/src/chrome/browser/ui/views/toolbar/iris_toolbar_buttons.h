// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris: the extra toolbar buttons (apply-toolbar-buttons.sh), one container view placed before the profile / menu
// buttons. Each button can be hidden in Settings -> Appearance.
//   Shield          Iris shield icon with the number of things blocked on this page; opens a panel (per-site switch for
//                   ads and trackers, canvas/audio reading, the counts, a link to Iris hardening).
//   JavaScript      turns JavaScript on or off for the current site (a per-site content setting) and reloads.
//   New identity    erases site data, cache, history and downloads, closes the other tabs and opens a fresh tab, and
//                   draws a new random seed for the canvas/audio protection. Asks you to click twice.
//   Lock and close  only when the app lock is on: quits Iris, so it asks for the passphrase next time.

#ifndef CHROME_BROWSER_UI_VIEWS_TOOLBAR_IRIS_TOOLBAR_BUTTONS_H_
#define CHROME_BROWSER_UI_VIEWS_TOOLBAR_IRIS_TOOLBAR_BUTTONS_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/iris/iris_shield_stats.h"  // nogncheck
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/prefs/pref_change_registrar.h"
#include "content/public/browser/web_contents_observer.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/view.h"
#include "ui/views/view_tracker.h"

class BrowserWindowInterface;
class ToolbarButton;

class IrisToolbarButtons : public views::View,
                           public TabStripModelObserver,
                           public content::WebContentsObserver,
                           public iris::ShieldStats::Observer {
  METADATA_HEADER(IrisToolbarButtons, views::View)

 public:
  static constexpr char kShieldPref[] = "iris.ui.toolbar_shield";
  static constexpr char kJavaScriptPref[] = "iris.ui.toolbar_javascript";
  static constexpr char kNewIdentityPref[] = "iris.ui.toolbar_new_identity";
  static constexpr char kLockPref[] = "iris.ui.toolbar_lock";

  explicit IrisToolbarButtons(BrowserWindowInterface* browser);
  IrisToolbarButtons(const IrisToolbarButtons&) = delete;
  IrisToolbarButtons& operator=(const IrisToolbarButtons&) = delete;
  ~IrisToolbarButtons() override;

  // views::View:
  void AddedToWidget() override;

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;

  // content::WebContentsObserver:
  void DidFinishNavigation(content::NavigationHandle* handle) override;

  // iris::ShieldStats::Observer:
  void OnShieldStatsChanged() override;

 private:
  void UpdateAll();
  void UpdateVisibility();
  void UpdateShield();
  void UpdateJavaScript();
  void BindToActiveTab();

  void OnShieldPressed();
  void OnShieldBubbleClosed();
  void OnJavaScriptPressed();
  void OnNewIdentityPressed();
  void OnLockPressed();
  void DisarmNewIdentity();

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<ToolbarButton> shield_ = nullptr;
  raw_ptr<ToolbarButton> javascript_ = nullptr;
  raw_ptr<ToolbarButton> new_identity_ = nullptr;
  raw_ptr<ToolbarButton> lock_ = nullptr;
  raw_ptr<iris::ShieldStats> stats_ = nullptr;
  bool new_identity_armed_ = false;
  base::OneShotTimer disarm_timer_;
  PrefChangeRegistrar pref_registrar_;
  views::ViewTracker shield_bubble_;
  base::TimeTicks shield_bubble_closed_at_;
  base::WeakPtrFactory<IrisToolbarButtons> weak_factory_{this};
};

#endif  // CHROME_BROWSER_UI_VIEWS_TOOLBAR_IRIS_TOOLBAR_BUTTONS_H_
