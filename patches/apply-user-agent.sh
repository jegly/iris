#!/usr/bin/env bash
# Iris — Phase B2: per-site browser identity (verified against this checkout 2026-09-27).
# Core: chrome/browser/iris/iris_user_agent.* (preset table + a tab helper that applies the site's preset in
# DidStartNavigation, the upstream "request desktop site" pattern; undoes only Iris's own override).
# Storage: website setting IRIS_USER_AGENT (apply-iris-permissions.sh). UI: Settings -> Site settings -> a site ->
# "Browser identity" (select: Iris (default) / Firefox on Linux / Chrome on Windows / Safari on macOS), backed by two
# SiteSettingsHandler messages (irisGetUserAgent / irisSetUserAgent). Strings from apply-iris-permissions.sh.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
mkdir -p chrome/browser/iris
for f in iris_user_agent.h iris_user_agent.cc; do
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
if "IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC" not in open("chrome/app/settings_strings.grdp").read():
    die("strings missing: run apply-iris-permissions.sh first")

edit("chrome/browser/BUILD.gn", "    \"iris/iris_google_signin_throttle.h\",  # Iris\n",
     "    \"iris/iris_google_signin_throttle.h\",  # Iris\n"
     "    \"iris/iris_user_agent.cc\",  # Iris\n    \"iris/iris_user_agent.h\",  # Iris\n",
     "iris/iris_user_agent.cc", "BUILD: sources")

t = "chrome/browser/ui/tab_helpers.cc"
edit(t, "  zoom::ZoomController::CreateForWebContents(web_contents);\n",
     "  zoom::ZoomController::CreateForWebContents(web_contents);\n"
     "  iris::UserAgentTabHelper::CreateForWebContents(web_contents);  // Iris (B2)\n",
     "iris::UserAgentTabHelper::CreateForWebContents", "tab helper attached")
edit(t, "#include \"chrome/browser/ui/tab_helpers.h\"\n",
     "#include \"chrome/browser/ui/tab_helpers.h\"\n"
     "#include \"chrome/browser/iris/iris_user_agent.h\"  // nogncheck  Iris (B2)\n",
     "chrome/browser/iris/iris_user_agent.h", "include")

hh = "chrome/browser/ui/webui/settings/site_settings_handler.h"
edit(hh, "  void HandleGetOriginPermissions(const base::ListValue& args);\n",
     "  void HandleGetOriginPermissions(const base::ListValue& args);\n"
     "  // Iris (B2): per-site browser identity.\n"
     "  void HandleIrisGetUserAgent(const base::ListValue& args);\n"
     "  void HandleIrisSetUserAgent(const base::ListValue& args);\n",
     "HandleIrisGetUserAgent", "handler declarations")
hc = "chrome/browser/ui/webui/settings/site_settings_handler.cc"
edit(hc, "void SiteSettingsHandler::RegisterMessages() {\n",
     "void SiteSettingsHandler::RegisterMessages() {\n"
     "  // Iris (B2)\n"
     "  web_ui()->RegisterMessageCallback(\n      \"irisGetUserAgent\",\n"
     "      base::BindRepeating(&SiteSettingsHandler::HandleIrisGetUserAgent,\n"
     "                          base::Unretained(this)));\n"
     "  web_ui()->RegisterMessageCallback(\n      \"irisSetUserAgent\",\n"
     "      base::BindRepeating(&SiteSettingsHandler::HandleIrisSetUserAgent,\n"
     "                          base::Unretained(this)));\n",
     "\"irisGetUserAgent\"", "messages registered")
impl = ('''
// Iris (B2): per-site browser identity (chrome/browser/iris/iris_user_agent.h).
void SiteSettingsHandler::HandleIrisGetUserAgent(const base::ListValue& args) {
  AllowJavascript();
  CHECK_EQ(2U, args.size());
  const base::Value& callback_id = args[0];
  const GURL origin(args[1].GetString());
  ResolveJavascriptCallback(
      callback_id, base::Value(iris::GetUserAgentPreset(profile_, origin)));
}

void SiteSettingsHandler::HandleIrisSetUserAgent(const base::ListValue& args) {
  CHECK_EQ(2U, args.size());
  iris::SetUserAgentPreset(profile_, GURL(args[0].GetString()),
                           args[1].GetString());
}

void SiteSettingsHandler::RegisterMessages() {
''')
edit(hc, "void SiteSettingsHandler::RegisterMessages() {\n  // Iris (B2)\n",
     impl + "  // Iris (B2)\n", "void SiteSettingsHandler::HandleIrisGetUserAgent", "handler implementation")
s = open(hc).read(); inc = '#include "chrome/browser/iris/iris_user_agent.h"  // Iris (B2)\n'
if inc not in s:
    a = '#include "chrome/browser/ui/webui/settings/site_settings_handler.h"\n'
    if s.count(a) != 1: die(hc + ": own include not found")
    open(hc, "w").write(s.replace(a, a + inc, 1)); print("OK   %s : include" % hc)

edit("chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc",
     "      {\"irisSiteSettingsWebgl\", IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL},  // Iris\n",
     "      {\"irisSiteSettingsWebgl\", IDS_SITE_SETTINGS_TYPE_IRIS_WEBGL},  // Iris\n"
     "      {\"irisUserAgent\", IDS_SETTINGS_IRIS_USER_AGENT},  // Iris (B2)\n"
     "      {\"irisUserAgentDefault\", IDS_SETTINGS_IRIS_USER_AGENT_DEFAULT},\n"
     "      {\"irisUserAgentFirefoxLinux\",\n       IDS_SETTINGS_IRIS_USER_AGENT_FIREFOX_LINUX},\n"
     "      {\"irisUserAgentChromeWindows\",\n       IDS_SETTINGS_IRIS_USER_AGENT_CHROME_WINDOWS},\n"
     "      {\"irisUserAgentSafariMac\", IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC},\n",
     "\"irisUserAgentFirefoxLinux\"", "strings registered")

d = "chrome/browser/resources/settings/site_settings/site_details.html"
edit(d, "    <style include=\"cr-shared-style settings-shared action-link\">\n",
     "    <style include=\"cr-shared-style settings-shared action-link md-select\">\n",
     "action-link md-select", "md-select style")
edit(d, "          label=\"$i18n{irisSiteSettingsGoogleSignin}\">\n      </site-details-permission>\n",
     "          label=\"$i18n{irisSiteSettingsGoogleSignin}\">\n      </site-details-permission>\n"
     "      <!-- Iris (B2): per-site browser identity (apply-user-agent.sh) -->\n"
     "      <div class=\"cr-row\" id=\"irisUserAgentRow\">\n"
     "        <div class=\"flex\">$i18n{irisUserAgent}</div>\n"
     "        <select class=\"md-select\" id=\"irisUserAgentSelect\"\n"
     "            aria-label=\"$i18n{irisUserAgent}\"\n"
     "            on-change=\"onIrisUserAgentChange_\">\n"
     "          <option value=\"\" selected=\"[[isIrisUserAgent_(irisUserAgent_, '')]]\">$i18n{irisUserAgentDefault}</option>\n"
     "          <option value=\"firefox_linux\" selected=\"[[isIrisUserAgent_(irisUserAgent_, 'firefox_linux')]]\">$i18n{irisUserAgentFirefoxLinux}</option>\n"
     "          <option value=\"chrome_windows\" selected=\"[[isIrisUserAgent_(irisUserAgent_, 'chrome_windows')]]\">$i18n{irisUserAgentChromeWindows}</option>\n"
     "          <option value=\"safari_mac\" selected=\"[[isIrisUserAgent_(irisUserAgent_, 'safari_mac')]]\">$i18n{irisUserAgentSafariMac}</option>\n"
     "        </select>\n"
     "      </div>\n",
     "irisUserAgentSelect", "identity picker")

ts = "chrome/browser/resources/settings/site_settings/site_details.ts"
edit(ts, "import {assert} from 'chrome://resources/js/assert.js';\n",
     "import {assert} from 'chrome://resources/js/assert.js';\n"
     "import {sendWithPromise} from 'chrome://resources/js/cr.js';  // Iris (B2)\n"
     "import 'chrome://resources/cr_elements/md_select.css.js';  // Iris (B2)\n",
     "sendWithPromise} from 'chrome://resources/js/cr.js';  // Iris", "imports")
edit(ts, "      origin_: String,\n",
     "      origin_: String,\n\n"
     "      // Iris (B2): the site's browser identity preset ('' = Iris default).\n"
     "      irisUserAgent_: {type: String, value: ''},\n",
     "irisUserAgent_: {type: String", "property")
edit(ts, "  declare private origin_: string;\n",
     "  declare private origin_: string;\n  declare private irisUserAgent_: string;  // Iris (B2)\n",
     "declare private irisUserAgent_", "property type")
edit(ts, "        this.storedData_ = '';\n        this.websiteUsageProxy_.fetchUsageTotal(this.origin_);\n",
     "        this.storedData_ = '';\n"
     "        // Iris (B2): load this site's browser identity.\n"
     "        sendWithPromise('irisGetUserAgent', this.origin_)\n"
     "            .then((preset) => {\n"
     "              this.irisUserAgent_ = preset as string;\n"
     "            });\n"
     "        this.websiteUsageProxy_.fetchUsageTotal(this.origin_);\n",
     "sendWithPromise('irisGetUserAgent'", "load on open")
edit(ts, "  override currentRouteChanged(route: Route, oldRoute?: Route) {\n",
     "  // Iris (B2)\n"
     "  private isIrisUserAgent_(current: string, preset: string): boolean {\n"
     "    return current === preset;\n  }\n\n"
     "  private onIrisUserAgentChange_(e: Event) {\n"
     "    const preset = (e.target as HTMLSelectElement).value;\n"
     "    this.irisUserAgent_ = preset;\n"
     "    chrome.send('irisSetUserAgent', [this.origin_, preset]);\n  }\n\n"
     "  override currentRouteChanged(route: Route, oldRoute?: Route) {\n",
     "private onIrisUserAgentChange_", "change handler")
PY
echo "=== per-site browser identity complete ==="
