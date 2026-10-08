#!/usr/bin/env bash
# Iris — one "Iris hardening" page for all of Iris's own switches (jegly 2026-10-08: "it would be easier if they are
# all under one place for users to find"; verified against 156.0.8078.11). Also adds "Hide the Install button".
# Desktop: Settings -> Privacy and security -> "Iris hardening" (new sub-page, route /irisHardening). The toggles the
#   other Iris patches put on the Privacy page (shredding, adblock-extra, privacy-toggles-1/2/3) are CUT from
#   privacy_page.html and regrouped (Ads and trackers / Web content / Fingerprinting / Network / Data / Address bar) into
#   the generated iris_hardening_page.html, so their wording stays defined in one place (those scripts).
#   New element: patches/src/.../privacy_page/iris_hardening_page.ts (copied). Wiring: route.ts, router.ts,
#   privacy_page_index.html, lazy_load.ts, BUILD.gn, privacy_page.ts (link row click, focus, search).
# Android: Privacy and security keeps one "Iris" section header for screenshots; the other Iris switches are moved into
#   topic categories at the end of the screen (PrivacySettings.java, by preference key).
# Hide the Install button: profile pref iris.ui.hide_install_button (registered by IrisShredder) ->
#   PwaInstallPageActionController::UpdateVisibility() hides the page action / chip (desktop). Installing still works
#   from the menu.
# Needs (in order): apply-shredder, apply-adblock-extra, apply-privacy-toggles-1/2/3, apply-android-iris-privacy-settings.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
TS=chrome/browser/resources/settings/privacy_page/iris_hardening_page.ts
from="$DIR/src/$TS"; [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
if cmp -s "$from" "$TS"; then echo "SKIP up to date: $TS"; else cp "$from" "$TS"; echo "OK   $TS"; fi
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
R = "chrome/browser/resources/settings/"
HIDE = "iris.ui.hide_install_button"

# 1. cut the Iris toggles from the Privacy page, generate the new page's template
p = R + "privacy_page/privacy_page.html"
out = R + "privacy_page/iris_hardening_page.html"
s = open(p).read()
if "irisHardeningLinkRow" in s:
    print("SKIP already applied: %s (toggles moved)" % p)
else:
    start = s.find("    <!-- Iris (B7): automatic data deletion, off by default (apply-shredder.sh) -->\n")
    end = s.find("    <cr-toast id=\"deleteBrowsingDataToast\"")
    if start < 0 or end < 0 or end < start: die("%s: Iris toggle block not found (run the toggle patches first)" % p)
    block = s[start:end]
    toggles = dict(re.findall(r'(    <settings-toggle-button id="(\w+)"[\s\S]*?</settings-toggle-button>\n)', block)[i][::-1]
                   for i in range(len(re.findall(r'<settings-toggle-button id="', block))))
    # keep search suggestions on the Privacy page (a standard Chromium setting, not an Iris one)
    keep = toggles.pop("irisSearchSuggestToggle", None)
    if keep is None: die("%s: search-suggestion toggle not in the block (drift?)" % p)
    toggles["irisHideInstallButtonToggle"] = (
        "    <settings-toggle-button id=\"irisHideInstallButtonToggle\" class=\"hr\"\n"
        "        pref-key=\"%s\"\n"
        "        label=\"Hide the &quot;Install&quot; button\"\n"
        "        sub-label=\"Websites that can be installed as apps no longer show an Install button in the address bar. "
        "You can still install them from the menu.\">\n"
        "    </settings-toggle-button>\n" % HIDE)
    GROUPS = [
        ("Ads and trackers", ["irisBlockAdsToggle", "irisAdblockExtraToggle"]),
        ("Web content", ["irisJavascriptOffToggle", "irisJitEverywhereToggle", "irisServiceWorkersOffToggle",
                         "irisWebglAllowToggle", "irisWebglOffToggle", "irisBlockWebFontsToggle",
                         "irisBlockAutoplayToggle", "irisGoogleSigninToggle", "irisExtensionsOffToggle"]),
        ("Fingerprinting", ["irisCoarseTimersToggle", "irisStandardLocaleToggle", "irisNoReferrersToggle"]),
        ("Network", ["irisQuicOffToggle"]),
        ("Data", ["irisShreddingToggle", "irisClearOnExitToggle", "irisMemoryCacheToggle",
                  "irisClearClipboardToggle", "irisDownloadAskToggle"]),
        ("Address bar", ["irisHideInstallButtonToggle"]),
    ]
    used = [i for _, ids in GROUPS for i in ids]
    missing = [i for i in used if i not in toggles]
    extra = [i for i in toggles if i not in used]
    if missing or extra: die("toggle set changed (missing %s, not grouped %s): update GROUPS" % (missing, extra))
    html = ("<!-- Generated by patches/apply-iris-hardening-page.sh from the Iris toggle patches. -->\n"
            "<style include=\"settings-shared\">\n"
            "  h2 {\n    padding-inline-start: var(--cr-section-padding);\n"
            "    padding-top: var(--cr-section-vertical-padding);\n  }\n"
            "  #intro {\n    padding: 0 var(--cr-section-padding) var(--cr-section-vertical-padding);\n  }\n"
            "</style>\n"
            "<settings-subpage page-title=\"Iris hardening\" route-path$=\"[[routePath]]\">\n"
            "  <div id=\"intro\" class=\"secondary\">Iris's own privacy and security switches. Most are off by "
            "default because they can break websites; turn on what you need.</div>\n")
    for title, ids in GROUPS:
        html += "  <h2>%s</h2>\n" % title + "".join(toggles[i] for i in ids)
    html += "</settings-subpage>\n"
    open(out, "w").write(html)
    row = ("    <!-- Iris: the Iris switches are on their own page (apply-iris-hardening-page.sh) -->\n"
           "    <cr-link-row id=\"irisHardeningLinkRow\" class=\"hr\" start-icon=\"cr:security\"\n"
           "        label=\"Iris hardening\"\n"
           "        sub-label=\"Ad blocking, JavaScript, WebGL, fonts, timers, cache, clear on exit and more\"\n"
           "        on-click=\"onIrisHardeningClick_\"\n"
           "        role-description=\"$i18n{subpageArrowRoleDescription}\"></cr-link-row>\n")
    open(p, "w").write(s[:start] + row + keep + s[end:])
    print("OK   %s : %d toggles moved to %s" % (p, len(used) - 1, out))

# 2. route + router
edit(R + "route.ts", "  r.SECURITY = r.PRIVACY.createChild('/security');\n",
     "  r.SECURITY = r.PRIVACY.createChild('/security');\n"
     "  r.IRIS_HARDENING = r.PRIVACY.createChild('/irisHardening');  // Iris\n",
     "r.IRIS_HARDENING", "route")
edit(R + "router.ts", "  COOKIES: Route;\n", "  COOKIES: Route;\n  IRIS_HARDENING: Route;  // Iris\n",
     "IRIS_HARDENING: Route;", "routes interface")
# 3. index
edit(R + "privacy_page/privacy_page_index.html",
     "  <template is=\"dom-if\" if=\"[[!enableBundledSecuritySettings_]]\">\n",
     "  <!-- Iris: apply-iris-hardening-page.sh -->\n"
     "  <template is=\"dom-if\" if=\"[[renderView_(\n"
     "      routes_.IRIS_HARDENING, currentRoute, inSearchMode)]]\"\n"
     "      update-when-false>\n"
     "    <settings-iris-hardening-page slot=\"view\" id=\"irisHardening\"\n"
     "        data-parent-view-id=\"privacy\" prefs=\"{{prefs}}\"\n"
     "        route-path$=\"[[routes_.IRIS_HARDENING.path]]\">\n"
     "    </settings-iris-hardening-page>\n"
     "  </template>\n\n"
     "  <template is=\"dom-if\" if=\"[[!enableBundledSecuritySettings_]]\">\n",
     "settings-iris-hardening-page", "index view")
# 4. lazy load + build
edit(R + "lazy_load.ts", "import './privacy_page/cookies_page.js';\n",
     "import './privacy_page/cookies_page.js';\nimport './privacy_page/iris_hardening_page.js';  // Iris\n",
     "iris_hardening_page.js';  // Iris\n", "lazy-load import")
edit(R + "lazy_load.ts", "export {SettingsCookiesPageElement} from './privacy_page/cookies_page.js';\n",
     "export {SettingsCookiesPageElement} from './privacy_page/cookies_page.js';\n"
     "export {SettingsIrisHardeningPageElement} from './privacy_page/iris_hardening_page.js';  // Iris\n",
     "export {SettingsIrisHardeningPageElement}", "lazy-load export")
edit(R + "BUILD.gn", "    \"privacy_page/cookies_page.ts\",\n",
     "    \"privacy_page/cookies_page.ts\",\n    \"privacy_page/iris_hardening_page.ts\",  # Iris\n",
     "privacy_page/iris_hardening_page.ts", "BUILD")
# 5. privacy page TS
t = R + "privacy_page/privacy_page.ts"
edit(t, "  private onCookiesClick_() {\n",
     "  // Iris: apply-iris-hardening-page.sh\n"
     "  private onIrisHardeningClick_() {\n"
     "    Router.getInstance().navigateTo(routes.IRIS_HARDENING);\n  }\n\n"
     "  private onCookiesClick_() {\n",
     "onIrisHardeningClick_() {", "link row click")
edit(t, "    if (routes.COOKIES) {\n      map.set(routes.COOKIES.path, '#thirdPartyCookiesLinkRow');\n    }\n",
     "    if (routes.COOKIES) {\n      map.set(routes.COOKIES.path, '#thirdPartyCookiesLinkRow');\n    }\n\n"
     "    if (routes.IRIS_HARDENING) {  // Iris\n"
     "      map.set(routes.IRIS_HARDENING.path, '#irisHardeningLinkRow');\n    }\n",
     "routes.IRIS_HARDENING.path, '#irisHardeningLinkRow'", "focus config")
edit(t, "      case 'cookies':\n        triggerId = 'thirdPartyCookiesLinkRow';\n        break;\n",
     "      case 'cookies':\n        triggerId = 'thirdPartyCookiesLinkRow';\n        break;\n"
     "      case 'irisHardening':  // Iris\n        triggerId = 'irisHardeningLinkRow';\n        break;\n",
     "case 'irisHardening':", "search highlight")
# 6. settings allowlist for the new pref
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % HIDE,
     "\"%s\"" % HIDE, "allowlist")
# 7. install button
q = "chrome/browser/ui/web_applications/pwa_install_page_action.cc"
edit(q, "  if (!manager_) {\n    return;\n  }\n\n  if (manager_->IsProbablyPromotableWebApp()) {\n",
     "  if (!manager_) {\n    return;\n  }\n\n"
     "  // Iris: Settings -> Iris hardening -> \"Hide the Install button\"\n"
     "  // (apply-iris-hardening-page.sh). Installing still works from the menu.\n"
     "  if (Profile::FromBrowserContext(web_contents->GetBrowserContext())\n"
     "          ->GetPrefs()\n"
     "          ->GetBoolean(\"%s\")) {\n"
     "    Hide();\n    return;\n  }\n\n"
     "  if (manager_->IsProbablyPromotableWebApp()) {\n" % HIDE,
     "GetBoolean(\"%s\")" % HIDE, "hide install button")
s = open(q).read()
if '#include "components/prefs/pref_service.h"' not in s:
    edit(q, '#include "components/site_engagement/content/site_engagement_service.h"\n',
         '#include "components/prefs/pref_service.h"  // Iris\n'
         '#include "components/site_engagement/content/site_engagement_service.h"\n',
         '#include "components/prefs/pref_service.h"  // Iris', "include")
# 8. Android: topic categories
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
AG = [("Ads and trackers", ["iris_block_ads", "iris_adblock_extra"]),
      ("Web content", ["iris_js_off", "iris_jit_everywhere", "iris_sw_off", "iris_webgl", "iris_webgl_off",
                       "iris_block_web_fonts", "iris_block_autoplay", "iris_google_signin"]),
      ("Fingerprinting", ["iris_coarse_timers", "iris_standard_locale", "iris_no_referrers"]),
      ("Network", ["iris_quic_off", "iris_strict_pq_tls"]),
      ("Data", ["iris_shredding", "iris_clear_on_exit", "iris_memory_cache", "iris_clear_clipboard",
                "iris_download_ask"])]
src = open(J).read()
for _, keys in AG:
    for k in keys:
        if '.setKey("%s");' % k not in src: die("%s: switch key %s not found (missing patch?)" % (J, k))
arr = "".join('            {"%s", %s},\n' % (t, ", ".join('"%s"' % k for k in keys)) for t, keys in AG)
edit(J, "        irisCategory.addPreference(irisJitEverywhere);\n",
     "        irisCategory.addPreference(irisJitEverywhere);\n"
     "        // Iris: group the Iris switches by topic (apply-iris-hardening-page.sh).\n"
     "        String[][] irisGroups = {\n" + arr + "        };\n"
     "        for (String[] group : irisGroups) {\n"
     "            androidx.preference.PreferenceCategory groupCategory =\n"
     "                    new androidx.preference.PreferenceCategory(getPreferenceManager().getContext());\n"
     "            groupCategory.setTitle(group[0]);\n"
     "            getPreferenceScreen().addPreference(groupCategory);\n"
     "            for (int i = 1; i < group.length; i++) {\n"
     "                androidx.preference.Preference irisPref = irisCategory.findPreference(group[i]);\n"
     "                if (irisPref == null) continue;\n"
     "                irisCategory.removePreference(irisPref);\n"
     "                groupCategory.addPreference(irisPref);\n"
     "            }\n"
     "        }\n",
     "String[][] irisGroups", "Android topic groups")
PY
echo "=== Iris hardening page complete ==="
