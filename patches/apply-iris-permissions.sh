#!/usr/bin/env bash
# Iris — Phase B batch: new per-site permissions (verified against this checkout 2026-09-27).
#   IRIS_WEBGL          (B1) WebGL per site, default BLOCK. Row in Page Info + Site settings.
#   IRIS_GOOGLE_SIGNIN  (B5) Google sign-in prompt frames (accounts.google.com/gsi, /o/oauth2/iframe) per site,
#                            default BLOCK (new chrome/browser/iris/iris_google_signin_throttle.*).
#   IRIS_USER_AGENT     (B2) website setting (a value per site) reserved here so the one expensive enum change is
#                            paid once; its logic/UI come with B2.
# COST: content_settings_types.mojom is included by thousands of files -> ONE long rebuild (hours). Everything that
# needs that rebuild is in this batch on purpose (enum, registry, histogram map, strings, Page Info, Settings).
# Guarded; idempotent (markers); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"

# new source files (B5 throttle)
mkdir -p chrome/browser/iris
for f in iris_google_signin_throttle.h iris_google_signin_throttle.cc; do
  from="$DIR/src/chrome/browser/iris/$f"; to="chrome/browser/iris/$f"
  [ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
  if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
done

python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

# 1. the enum
edit("components/content_settings/core/common/content_settings_types.mojom",
     "  // Stores allowlist decisions for Suspicious Site Warnings.\n  SUSPICIOUS_SITE_WARNING_DATA,\n};\n",
     "  // Stores allowlist decisions for Suspicious Site Warnings.\n  SUSPICIOUS_SITE_WARNING_DATA,\n\n"
     "  // Iris: WebGL per site (default BLOCK). patches/apply-iris-permissions.sh\n  IRIS_WEBGL,\n\n"
     "  // Iris: Google sign-in prompt frames (One Tap / Sign in with Google) per site\n"
     "  // (default BLOCK).\n  IRIS_GOOGLE_SIGNIN,\n\n"
     "  // Iris: per-site user agent choice (website setting, a value).\n  IRIS_USER_AGENT,\n};\n",
     "IRIS_WEBGL,", "IRIS_* content setting types")

# 2. histogram map (compile-time size check)
edit("components/content_settings/core/common/content_settings_uma_constants.h",
     "        {ContentSettingsType::SUSPICIOUS_SITE_WARNING_DATA, 147},\n",
     "        {ContentSettingsType::SUSPICIOUS_SITE_WARNING_DATA, 147},\n"
     "        // Iris types (not reported anywhere: Iris has no metrics).\n"
     "        {ContentSettingsType::IRIS_WEBGL, 148},\n"
     "        {ContentSettingsType::IRIS_GOOGLE_SIGNIN, 149},\n"
     "        {ContentSettingsType::IRIS_USER_AGENT, 150},\n",
     "ContentSettingsType::IRIS_WEBGL, 148", "histogram values")

# 3. registries
reg = lambda t, n: ("  Register(ContentSettingsType::%s, \"%s\",\n"
    "           CONTENT_SETTING_BLOCK, WebsiteSettingsInfo::UNSYNCABLE,\n"
    "           /*allowlisted_primary_schemes=*/{},\n"
    "           /*valid_settings=*/{CONTENT_SETTING_ALLOW, CONTENT_SETTING_BLOCK},\n"
    "           WebsiteSettingsInfo::TOP_ORIGIN_ONLY_SCOPE,\n"
    "           WebsiteSettingsRegistry::DESKTOP |\n"
    "               WebsiteSettingsRegistry::PLATFORM_ANDROID,\n"
    "           ContentSettingsInfo::INHERIT_IN_INCOGNITO,\n"
    "           PermissionSettingsInfo::EXCEPTIONS_ON_SECURE_AND_INSECURE_ORIGINS);\n\n") % (t, n)
anchor = "  Register(ContentSettingsType::JAVASCRIPT_OPTIMIZER, \"javascript-optimizer\",\n"
edit("components/content_settings/core/browser/content_settings_registry.cc", anchor,
     "  // Iris (apply-iris-permissions.sh): per-site switches, BLOCK by default.\n" +
     reg("IRIS_WEBGL", "iris-webgl") + reg("IRIS_GOOGLE_SIGNIN", "iris-google-signin") + anchor,
     "ContentSettingsType::IRIS_WEBGL", "register IRIS_WEBGL + IRIS_GOOGLE_SIGNIN")
a = ("  Register(ContentSettingsType::HTTP_ALLOWED, \"http-allowed\", base::Value(),\n"
     "           WebsiteSettingsInfo::UNSYNCABLE, WebsiteSettingsInfo::NOT_LOSSY,\n"
     "           WebsiteSettingsInfo::GENERIC_SINGLE_ORIGIN_SCOPE, ALL_PLATFORMS,\n"
     "           WebsiteSettingsInfo::DONT_INHERIT_IN_INCOGNITO);\n")
edit("components/content_settings/core/browser/website_settings_registry.cc", a,
     a + "  // Iris (apply-iris-permissions.sh): per-site user agent choice (B2).\n"
     "  Register(ContentSettingsType::IRIS_USER_AGENT, \"iris-user-agent\",\n"
     "           base::Value(), WebsiteSettingsInfo::UNSYNCABLE,\n"
     "           WebsiteSettingsInfo::NOT_LOSSY,\n"
     "           WebsiteSettingsInfo::GENERIC_SINGLE_ORIGIN_SCOPE, ALL_PLATFORMS,\n"
     "           WebsiteSettingsInfo::INHERIT_IN_INCOGNITO);\n",
     "ContentSettingsType::IRIS_USER_AGENT", "register IRIS_USER_AGENT")

# 4. strings (one file; Settings reuses them like the JavaScript optimizer row does)
msgs = ("  <!-- Iris (apply-iris-permissions.sh) -->\n"
  "  <message name=\"IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL\" desc=\"Name of the Iris per-site WebGL (3D graphics) setting.\">\n"
  "    WebGL (3D graphics)\n  </message>\n"
  "  <message name=\"IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL_MID_SENTENCE\" desc=\"Name of the Iris per-site WebGL setting when used mid-sentence.\">\n"
  "    WebGL (3D graphics)\n  </message>\n"
  "  <message name=\"IDS_SITE_SETTINGS_TYPE_IRIS_GOOGLE_SIGNIN\" desc=\"Name of the Iris per-site setting that allows Google sign-in prompts (One Tap, Sign in with Google buttons) embedded in a site.\">\n"
  "    Google sign-in prompts\n  </message>\n"
  "  <message name=\"IDS_SITE_SETTINGS_TYPE_IRIS_GOOGLE_SIGNIN_MID_SENTENCE\" desc=\"Mid-sentence form of the Iris Google sign-in prompts setting.\">\n"
  "    Google sign-in prompts\n  </message>\n")
p = "components/site_settings_strings.grdp"
s = open(p).read()
if "IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL" in s: print("SKIP already applied: %s (strings)" % p)
else:
    if s.count("</grit-part>") != 1: die(p + ": </grit-part> not found once")
    open(p, "w").write(s.replace("</grit-part>", msgs + "</grit-part>")); print("OK   %s : strings" % p)

# 4b. Strings for later Phase B UI, added NOW so the long rebuild is paid once (a new message changes the generated
#     IDs header that thousands of files include): B12 extension toggle (translatable), B7 shredding, B2 identity.
def add_msgs(p, key, block, label):
    s = open(p).read()
    if key in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count("</grit-part>") != 1: die(p + ": </grit-part> not found once")
    open(p, "w").write(s.replace("</grit-part>", block + "</grit-part>")); print("OK   %s : %s" % (p, label))
M = lambda n, d, t: "  <message name=\"%s\" desc=\"%s\">\n    %s\n  </message>\n" % (n, d, t)
add_msgs("chrome/app/settings_strings.grdp", "IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE",
  "  <!-- Iris (apply-iris-permissions.sh) -->\n" +
  M("IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE", "Iris: label of the toggle that lets extensions update automatically.", "Update extensions automatically") +
  M("IDS_SETTINGS_IRIS_EXTENSION_AUTO_UPDATE_SUBLABEL", "Iris: explanation under the extension auto-update toggle.", "Checks the Chrome Web Store for extension updates, including security fixes. Google then sees which extensions you have installed.") +
  M("IDS_SETTINGS_IRIS_SHREDDING", "Iris: label of the toggle that deletes browsing data automatically after a while.", "Delete browsing data automatically") +
  M("IDS_SETTINGS_IRIS_SHREDDING_SUBLABEL", "Iris: explanation under the automatic data deletion toggle.", "Cookies and site data after 24 hours, cached files after 12 hours, the downloads list after 7 days, and text copied in Iris from the clipboard after 30 seconds.") +
  M("IDS_SETTINGS_IRIS_USER_AGENT", "Iris: per-site setting that chooses which browser the site is told it is talking to.", "Browser identity") +
  M("IDS_SETTINGS_IRIS_USER_AGENT_DEFAULT", "Iris: browser identity option: the normal Iris identity.", "Iris (default)") +
  M("IDS_SETTINGS_IRIS_USER_AGENT_FIREFOX_LINUX", "Iris: browser identity option.", "Firefox on Linux") +
  M("IDS_SETTINGS_IRIS_USER_AGENT_CHROME_WINDOWS", "Iris: browser identity option.", "Chrome on Windows") +
  M("IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC", "Iris: browser identity option.", "Safari on macOS"),
  "Phase B strings (settings)")
add_msgs("components/page_info_strings.grdp", "IDS_PAGE_INFO_IRIS_FORGET_SITE",
  "  <!-- Iris (apply-iris-permissions.sh) -->\n" +
  M("IDS_PAGE_INFO_IRIS_FORGET_SITE", "Iris: Page Info button that makes the browser delete this site's data when it closes.", "Forget this site when I close Iris") +
  M("IDS_PAGE_INFO_IRIS_FORGET_SITE_ON", "Iris: Page Info state shown when the site's data will be deleted when the browser closes.", "This site's data is deleted when you close Iris"),
  "Phase B strings (Page Info)")

# 4c. (2026-09-27, second pass before the long build) B4 per-site "Canvas and audio reading" (website setting,
#     value "protected" | "blank" | "real"; unset = protected) + ALL B4/B8/B10 strings, so those features ship with
#     short builds only. Separate markers so an already-patched tree is upgraded in place.
edit("components/content_settings/core/common/content_settings_types.mojom",
     "  // Iris: per-site user agent choice (website setting, a value).\n  IRIS_USER_AGENT,\n};\n",
     "  // Iris: per-site user agent choice (website setting, a value).\n  IRIS_USER_AGENT,\n\n"
     "  // Iris: per-site canvas/audio read mode (website setting: protected | blank |\n"
     "  // real; unset = protected).\n  IRIS_FINGERPRINT_READS,\n};\n",
     "IRIS_FINGERPRINT_READS,", "IRIS_FINGERPRINT_READS type")
edit("components/content_settings/core/common/content_settings_uma_constants.h",
     "        {ContentSettingsType::IRIS_USER_AGENT, 150},\n",
     "        {ContentSettingsType::IRIS_USER_AGENT, 150},\n"
     "        {ContentSettingsType::IRIS_FINGERPRINT_READS, 151},\n",
     "IRIS_FINGERPRINT_READS, 151", "histogram value 151")
a4 = ("  Register(ContentSettingsType::IRIS_USER_AGENT, \"iris-user-agent\",\n")
edit("components/content_settings/core/browser/website_settings_registry.cc", a4,
     "  // Iris (B4): per-site canvas/audio read mode.\n"
     "  Register(ContentSettingsType::IRIS_FINGERPRINT_READS, \"iris-fingerprint-reads\",\n"
     "           base::Value(), WebsiteSettingsInfo::UNSYNCABLE,\n"
     "           WebsiteSettingsInfo::NOT_LOSSY,\n"
     "           WebsiteSettingsInfo::GENERIC_SINGLE_ORIGIN_SCOPE, ALL_PLATFORMS,\n"
     "           WebsiteSettingsInfo::INHERIT_IN_INCOGNITO);\n" + a4,
     "ContentSettingsType::IRIS_FINGERPRINT_READS, \"iris-fingerprint-reads\"", "register IRIS_FINGERPRINT_READS")
M2 = lambda n, d, t: "  <message name=\"%s\" desc=\"%s\">\n    %s\n  </message>\n" % (n, d, t)
add_msgs("chrome/app/settings_strings.grdp", "IDS_SETTINGS_IRIS_FINGERPRINT_READS",
  "  <!-- Iris B4/B8/B10 (apply-iris-permissions.sh 4c) -->\n" +
  M2("IDS_SETTINGS_IRIS_FINGERPRINT_READS", "Iris: per-site setting for what sites get when they read canvas drawings or audio.", "Canvas and audio reading") +
  M2("IDS_SETTINGS_IRIS_FINGERPRINT_READS_SUBLABEL", "Iris: explanation of the canvas and audio reading setting.", "Sites that read drawings or sound from the page to identify your device get slightly changed results.") +
  M2("IDS_SETTINGS_IRIS_FINGERPRINT_READS_PROTECTED", "Iris: canvas/audio reading option: slightly changed results (default).", "Protected (default)") +
  M2("IDS_SETTINGS_IRIS_FINGERPRINT_READS_BLANK", "Iris: canvas/audio reading option: empty results.", "Blank") +
  M2("IDS_SETTINGS_IRIS_FINGERPRINT_READS_REAL", "Iris: canvas/audio reading option: unchanged results.", "Real data") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK", "Iris: toggle/section that locks the browser with a passphrase.", "Lock Iris with a passphrase") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_SUBLABEL", "Iris: explanation of the app lock.", "Asks for your passphrase when Iris starts. Your cookies, saved logins, bookmarks and open tabs are encrypted with it.") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_SET", "Iris: button to set the app lock passphrase.", "Set passphrase") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_CHANGE", "Iris: button to change the app lock passphrase.", "Change passphrase") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_REMOVE", "Iris: button to turn the app lock off.", "Turn off app lock") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_AFTER", "Iris: setting for how long until Iris locks again.", "Lock again after") +
  M2("IDS_SETTINGS_IRIS_APP_LOCK_WARNING", "Iris: warning shown when setting the passphrase.", "If you forget this passphrase, your encrypted data can't be recovered.") +
  M2("IDS_IRIS_UNLOCK_TITLE", "Iris: title of the lock screen.", "Iris is locked") +
  M2("IDS_IRIS_UNLOCK_PROMPT", "Iris: lock screen passphrase field label.", "Enter your passphrase") +
  M2("IDS_IRIS_UNLOCK_BUTTON", "Iris: lock screen button.", "Unlock") +
  M2("IDS_IRIS_UNLOCK_WRONG", "Iris: lock screen error.", "Wrong passphrase. Try again.") +
  M2("IDS_IRIS_UNLOCK_QUIT", "Iris: lock screen button that closes the browser.", "Quit"),
  "B4/B8/B10 strings")

# 5. Page Info: rows always shown, names
edit("components/page_info/page_info.cc",
     "    ContentSettingsType::ADS,\n    ContentSettingsType::BACKGROUND_SYNC,\n",
     "    ContentSettingsType::ADS,\n"
     "    ContentSettingsType::IRIS_WEBGL,          // Iris\n"
     "    ContentSettingsType::IRIS_GOOGLE_SIGNIN,  // Iris\n"
     "    ContentSettingsType::BACKGROUND_SYNC,\n",
     "ContentSettingsType::IRIS_WEBGL,          // Iris", "Page Info rows")
edit("components/page_info/page_info.cc",
     "  // Note |ContentSettingsType::ADS| will show up regardless of its default\n",
     "  // Iris: its per-site switches are always offered on the site's Page Info.\n"
     "  if (info.type == ContentSettingsType::IRIS_WEBGL ||\n"
     "      info.type == ContentSettingsType::IRIS_GOOGLE_SIGNIN) {\n"
     "    return true;\n"
     "  }\n\n"
     "  // Note |ContentSettingsType::ADS| will show up regardless of its default\n",
     "per-site switches are always offered", "Page Info always shows Iris rows")
edit("components/page_info/page_info_ui.cc",
     "      {ContentSettingsType::ADS, IDS_SITE_SETTINGS_TYPE_ADS,\n       IDS_SITE_SETTINGS_TYPE_ADS_MID_SENTENCE},\n",
     "      {ContentSettingsType::ADS, IDS_SITE_SETTINGS_TYPE_ADS,\n       IDS_SITE_SETTINGS_TYPE_ADS_MID_SENTENCE},\n"
     "      // Iris\n"
     "      {ContentSettingsType::IRIS_WEBGL, IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL,\n"
     "       IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL_MID_SENTENCE},\n"
     "      {ContentSettingsType::IRIS_GOOGLE_SIGNIN,\n"
     "       IDS_SITE_SETTINGS_TYPE_IRIS_GOOGLE_SIGNIN,\n"
     "       IDS_SITE_SETTINGS_TYPE_IRIS_GOOGLE_SIGNIN_MID_SENTENCE},\n",
     "IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL,", "Page Info names")

# 6. Settings (Site settings -> a site): type names, rows, strings
h = "chrome/browser/ui/webui/settings/site_settings_helper.cc"
edit(h, "    {ContentSettingsType::JAVASCRIPT_OPTIMIZER, \"javascript-optimizer\"},\n",
     "    {ContentSettingsType::JAVASCRIPT_OPTIMIZER, \"javascript-optimizer\"},\n"
     "    {ContentSettingsType::IRIS_WEBGL, \"iris-webgl\"},                  // Iris\n"
     "    {ContentSettingsType::IRIS_GOOGLE_SIGNIN, \"iris-google-signin\"},  // Iris\n"
     "    {ContentSettingsType::IRIS_USER_AGENT, nullptr},                   // Iris\n"
     "    {ContentSettingsType::IRIS_FINGERPRINT_READS, nullptr},            // Iris\n",
     "\"iris-webgl\"},", "Settings type names")
s_h = open("chrome/browser/ui/webui/settings/site_settings_helper.cc").read()
if "IRIS_USER_AGENT, nullptr" not in s_h and "\"iris-webgl\"}," in s_h:  # upgrade an older apply
    old = "    {ContentSettingsType::IRIS_GOOGLE_SIGNIN, \"iris-google-signin\"},  // Iris\n"
    if s_h.count(old) != 1: die(h + ": cannot upgrade type names")
    open("chrome/browser/ui/webui/settings/site_settings_helper.cc","w").write(s_h.replace(old, old + "    {ContentSettingsType::IRIS_USER_AGENT, nullptr},                   // Iris\n"))
    print("OK   %s : IRIS_USER_AGENT listed (upgrade)" % h)
s_h = open("chrome/browser/ui/webui/settings/site_settings_helper.cc").read()
if "IRIS_FINGERPRINT_READS, nullptr" not in s_h and "IRIS_USER_AGENT, nullptr" in s_h:
    o3 = "    {ContentSettingsType::IRIS_USER_AGENT, nullptr},                   // Iris\n"
    open("chrome/browser/ui/webui/settings/site_settings_helper.cc","w").write(s_h.replace(o3, o3 + "    {ContentSettingsType::IRIS_FINGERPRINT_READS, nullptr},            // Iris\n"))
    print("OK   %s : IRIS_FINGERPRINT_READS listed (upgrade)" % h)
edit(h, "      ContentSettingsType::JAVASCRIPT,\n      ContentSettingsType::JAVASCRIPT_OPTIMIZER,\n      ContentSettingsType::LOCAL_FONTS,\n",
     "      ContentSettingsType::JAVASCRIPT,\n      ContentSettingsType::JAVASCRIPT_OPTIMIZER,\n"
     "      ContentSettingsType::IRIS_WEBGL,          // Iris\n"
     "      ContentSettingsType::IRIS_GOOGLE_SIGNIN,  // Iris\n"
     "      ContentSettingsType::LOCAL_FONTS,\n",
     "      ContentSettingsType::IRIS_WEBGL,          // Iris\n", "Settings per-site list")
edit("chrome/browser/resources/settings/site_settings/constants.ts",
     "  JAVASCRIPT_OPTIMIZER = 'javascript-optimizer',\n",
     "  JAVASCRIPT_OPTIMIZER = 'javascript-optimizer',\n"
     "  IRIS_WEBGL = 'iris-webgl',  // Iris\n"
     "  IRIS_GOOGLE_SIGNIN = 'iris-google-signin',  // Iris\n",
     "IRIS_WEBGL = 'iris-webgl'", "Settings TS enum")
edit("chrome/browser/resources/settings/site_settings/site_details.html",
     "          icon=\"privacy:v8\"\n          label=\"$i18n{siteSettingsJavascriptOptimizer}\">\n      </site-details-permission>\n",
     "          icon=\"privacy:v8\"\n          label=\"$i18n{siteSettingsJavascriptOptimizer}\">\n      </site-details-permission>\n"
     "      <!-- Iris (apply-iris-permissions.sh) -->\n"
     "      <site-details-permission\n"
     "          category=\"[[contentSettingsTypesEnum_.IRIS_WEBGL]]\"\n"
     "          icon=\"privacy:select-window\"\n"
     "          label=\"$i18n{irisSiteSettingsWebgl}\">\n"
     "      </site-details-permission>\n"
     "      <site-details-permission\n"
     "          category=\"[[contentSettingsTypesEnum_.IRIS_GOOGLE_SIGNIN]]\"\n"
     "          icon=\"privacy:account-circle\"\n"
     "          label=\"$i18n{irisSiteSettingsGoogleSignin}\">\n"
     "      </site-details-permission>\n",
     "irisSiteSettingsWebgl", "Site details rows")
edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"siteSettingsJavascriptOptimizer\",\n       IDS_SITE_SETTINGS_TYPE_JAVASCRIPT_OPTIMIZER},\n",
     "      {\"siteSettingsJavascriptOptimizer\",\n       IDS_SITE_SETTINGS_TYPE_JAVASCRIPT_OPTIMIZER},\n"
     "      {\"irisSiteSettingsWebgl\", IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL},  // Iris\n"
     "      {\"irisSiteSettingsGoogleSignin\",\n"
     "       IDS_SITE_SETTINGS_TYPE_IRIS_GOOGLE_SIGNIN},  // Iris\n",
     "\"irisSiteSettingsWebgl\"", "Settings strings")

# 7. B1 gate: WebGL only where allowed
c = "chrome/browser/chrome_content_browser_client.cc"
edit(c, "  if (prefs->GetBoolean(prefs::kDisable3DAPIs)) {\n"
        "    web_prefs->webgl1_enabled = false;\n    web_prefs->webgl2_enabled = false;\n  }\n",
     "  if (prefs->GetBoolean(prefs::kDisable3DAPIs)) {\n"
     "    web_prefs->webgl1_enabled = false;\n    web_prefs->webgl2_enabled = false;\n  }\n"
     "  // Iris: WebGL off unless the site is allowed (ContentSettingsType::IRIS_WEBGL).\n"
     "  if (!IrisWebGLAllowed(web_contents, web_contents->GetVisibleURL())) {\n"
     "    web_prefs->webgl1_enabled = false;\n    web_prefs->webgl2_enabled = false;\n  }\n",
     "if (!IrisWebGLAllowed(web_contents, web_contents->GetVisibleURL()))", "WebGL gate (initial prefs)")
edit(c, "  for (auto& parts : extra_parts_) {\n    prefs_changed |= parts->OverrideWebPreferencesAfterNavigation(\n",
     "  // Iris: WebGL per site (ContentSettingsType::IRIS_WEBGL, default BLOCK).\n"
     "  {\n"
     "    const bool iris_webgl =\n"
     "        !Profile::FromBrowserContext(web_contents->GetBrowserContext())\n"
     "             ->GetPrefs()\n"
     "             ->GetBoolean(prefs::kDisable3DAPIs) &&\n"
     "        IrisWebGLAllowed(web_contents, web_contents->GetLastCommittedURL());\n"
     "    prefs_changed |= web_prefs->webgl1_enabled != iris_webgl ||\n"
     "                     web_prefs->webgl2_enabled != iris_webgl;\n"
     "    web_prefs->webgl1_enabled = iris_webgl;\n"
     "    web_prefs->webgl2_enabled = iris_webgl;\n"
     "  }\n\n"
     "  for (auto& parts : extra_parts_) {\n    prefs_changed |= parts->OverrideWebPreferencesAfterNavigation(\n",
     "WebGL per site (ContentSettingsType::IRIS_WEBGL, default BLOCK).\n  {", "WebGL gate (after navigation)")
edit(c, "void ChromeContentBrowserClient::OverrideWebPreferences(\n",
     "namespace {\n"
     "// Iris: is WebGL allowed for `url` (per-site IRIS_WEBGL, default BLOCK)?\n"
     "bool IrisWebGLAllowed(content::WebContents* web_contents, const GURL& url) {\n"
     "  if (!url.is_valid()) {\n    return false;\n  }\n"
     "  HostContentSettingsMap* map = HostContentSettingsMapFactory::GetForProfile(\n"
     "      web_contents->GetBrowserContext());\n"
     "  return map && map->GetContentSetting(url, url,\n"
     "                                       ContentSettingsType::IRIS_WEBGL) ==\n"
     "                    CONTENT_SETTING_ALLOW;\n"
     "}\n"
     "}  // namespace\n\n"
     "void ChromeContentBrowserClient::OverrideWebPreferences(\n",
     "bool IrisWebGLAllowed(content::WebContents* web_contents", "IrisWebGLAllowed helper")

# 8. B5 throttle: build + registration
edit("chrome/browser/BUILD.gn",
     "    \"chrome_content_browser_client_navigation_throttles.cc\",\n",
     "    \"chrome_content_browser_client_navigation_throttles.cc\",\n"
     "    \"iris/iris_google_signin_throttle.cc\",  # Iris\n"
     "    \"iris/iris_google_signin_throttle.h\",  # Iris\n",
     "iris/iris_google_signin_throttle.cc", "BUILD: throttle sources")
t = "chrome/browser/chrome_content_browser_client_navigation_throttles.cc"
edit(t, "#include \"chrome/browser/chrome_content_browser_client_navigation_throttles.h\"\n",
     "#include \"chrome/browser/chrome_content_browser_client_navigation_throttles.h\"\n"
     "#include \"chrome/browser/iris/iris_google_signin_throttle.h\"  // Iris\n",
     "iris_google_signin_throttle.h", "throttle include")
edit(t, "  content::NavigationHandle& handle = registry.GetNavigationHandle();\n  if (handle.IsInMainFrame()) {\n"
        "    // MetricsNavigationThrottle requires",
     "  content::NavigationHandle& handle = registry.GetNavigationHandle();\n"
     "  // Iris: Google sign-in prompt frames need the site's permission (B5).\n"
     "  IrisGoogleSigninThrottle::MaybeCreateAndAdd(registry);\n"
     "  if (handle.IsInMainFrame()) {\n    // MetricsNavigationThrottle requires",
     "IrisGoogleSigninThrottle::MaybeCreateAndAdd(registry);", "throttle registration")
PY
echo "=== Iris permissions batch complete ==="
