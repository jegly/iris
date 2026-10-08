#!/usr/bin/env bash
# Iris — hardening toggles, part 3 (jegly 2026-10-08; verified against 156.0.8078.11). Needs apply-shredder.sh
# (prefs in patches/src/chrome/browser/iris/iris_shredder.*), apply-iris-permissions.sh, apply-adblock.sh,
# apply-privacy-toggles-2.sh (anchors). Off by default unless said:
#  10. Block fonts downloaded by websites  iris.privacy.block_web_fonts -> WebPreferences.remote_fonts_enabled = false
#      (Blink SetDownloadableBinaryFontsEnabled), set in OverrideWebPreferences and after each navigation.
#  11. Don't tell websites where you came from   Chromium's enable_referrers (prefs_tab_helper.cc; live via
#      PrefWatcher + ProfileNetworkContextService). Toggle is inverted.
#  12. Turn off QUIC (HTTP/3)   Chromium's profile pref net.quic_allowed (default true - QUIC stays ON by default,
#      jegly: "a lot of sites use QUIC"). Upstream only honoured it when set by policy
#      (DisableQuicIfNotAllowed: `if (!quic_allowed_.IsManaged()) return;`); that gate is removed so the user's setting
#      counts. Turning QUIC off is immediate; back on needs a restart (upstream cannot re-enable it live).
#  13. Block autoplaying media   iris.privacy.block_autoplay -> DetermineWebContentsAutoplayPolicy returns
#      kUserGestureRequired (every audio/video needs a click). New pages.
#  14. Clear copied text after 30 seconds   iris.privacy.clear_clipboard (split out of automatic deletion; profiles that
#      had deletion on keep it on - see iris_shredder.cc). The deletion descriptions drop the clipboard sentence.
#  15. Faster JavaScript (JIT) on every site   default of ContentSettingsType::JAVASCRIPT_JIT (Iris default BLOCK).
#  16. Block ads and trackers (ON by default)   default of ContentSettingsType::ADS (subresource filter; BLOCK = filter on).
#  17. Allow WebGL on all sites / 18. Allow "Sign in with Google" prompts   defaults of IRIS_WEBGL / IRIS_GOOGLE_SIGNIN
#      (desktop; Android already has these two switches).
# Desktop: Settings -> Privacy and security; Android: Privacy and security -> Iris. English-only labels.
# STATUS 2026-10-08: copy-tested only, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
import os
IRIS_HARDENING = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
def moved(toggle_id):  # moved to the Iris hardening page by apply-iris-hardening-page.sh
    return os.path.exists(IRIS_HARDENING) and toggle_id in open(IRIS_HARDENING).read()
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

FONTS, AUTO, CLIP = "iris.privacy.block_web_fonts", "iris.privacy.block_autoplay", "iris.privacy.clear_clipboard"
D = "profile.default_content_setting_values."
T = {
 "fonts": ("Block fonts downloaded by websites",
           "Websites use your system fonts instead of downloading their own. Font files are a common route for attacks "
           "and for identifying you. Some icons may show as boxes."),
 "ref":   ("Don't tell websites where you came from",
           "Iris stops sending the Referer header, so a site can't see which page linked you to it. A few logins or "
           "payments may fail."),
 "quic":  ("Turn off QUIC (HTTP/3)",
           "Iris uses only TCP connections (HTTP/2 and older). Removes a large network component; some sites may load a "
           "little slower. Turning QUIC back on needs a restart."),
 "auto":  ("Block autoplaying media",
           "Video and audio only play after you click them. Applies to pages opened after you change it."),
 "clip":  ("Clear copied text after 30 seconds",
           "Text you copy in Iris is removed from the clipboard after 30 seconds, if it is still there."),
 "jit":   ("Faster JavaScript (JIT) on every site",
           "Turns the JavaScript optimiser and WebAssembly back on for all sites. Faster, but brings back a large attack "
           "surface that Iris removes by default. You can also allow it for single sites from the lock icon."),
 "ads":   ("Block ads and trackers",
           "Iris's built-in blocker on all sites. You can still allow ads for a single site from the lock icon."),
 "gl":    ("Allow WebGL on all sites",
           "3D graphics for every website without asking. Off by default: WebGL exposes details of your graphics "
           "hardware. \\\"Turn WebGL off completely\\\" overrides this."),
 "gs":    ("Allow \\\"Sign in with Google\\\" prompts",
           "Google's sign-in pop-ups on other websites. Off by default. Signing in on Google's own sites is not affected."),
}

c = "chrome/browser/chrome_content_browser_client.cc"
edit(c,
     "  if (!IrisWebGLAllowed(web_contents, web_contents->GetVisibleURL())) {\n"
     "    web_prefs->webgl1_enabled = false;\n    web_prefs->webgl2_enabled = false;\n  }\n",
     "  if (!IrisWebGLAllowed(web_contents, web_contents->GetVisibleURL())) {\n"
     "    web_prefs->webgl1_enabled = false;\n    web_prefs->webgl2_enabled = false;\n  }\n"
     "  // Iris: Settings -> \"Block fonts downloaded by websites\"\n"
     "  // (apply-privacy-toggles-3.sh).\n"
     "  if (prefs->GetBoolean(\"%s\")) {\n"
     "    web_prefs->remote_fonts_enabled = false;\n  }\n" % FONTS,
     "web_prefs->remote_fonts_enabled = false;", "fonts (initial prefs)")
edit(c,
     "    web_prefs->webgl1_enabled = iris_webgl;\n    web_prefs->webgl2_enabled = iris_webgl;\n  }\n",
     "    web_prefs->webgl1_enabled = iris_webgl;\n    web_prefs->webgl2_enabled = iris_webgl;\n  }\n"
     "  // Iris: \"Block fonts downloaded by websites\" (apply-privacy-toggles-3.sh).\n"
     "  {\n"
     "    const bool iris_fonts =\n"
     "        !Profile::FromBrowserContext(web_contents->GetBrowserContext())\n"
     "             ->GetPrefs()\n"
     "             ->GetBoolean(\"%s\");\n"
     "    prefs_changed |= web_prefs->remote_fonts_enabled != iris_fonts;\n"
     "    web_prefs->remote_fonts_enabled = iris_fonts;\n"
     "  }\n" % FONTS,
     "const bool iris_fonts =", "fonts (after navigation)")
edit(c,
     "  AutoplayPolicyStatusObserver* observer =\n"
     "      AutoplayPolicyStatusObserver::GetOrCreateForWebContents(web_contents);\n",
     "  AutoplayPolicyStatusObserver* observer =\n"
     "      AutoplayPolicyStatusObserver::GetOrCreateForWebContents(web_contents);\n\n"
     "  // Iris: Settings -> \"Block autoplaying media\": every audio and video needs\n"
     "  // a click (apply-privacy-toggles-3.sh).\n"
     "  if (prefs->GetBoolean(\"%s\")) {\n"
     "    return blink::mojom::AutoplayPolicy::kUserGestureRequired;\n"
     "  }\n" % AUTO,
     "GetBoolean(\"%s\")) {\n    return blink::mojom::AutoplayPolicy::kUserGestureRequired" % AUTO, "autoplay")

edit("chrome/browser/net/profile_network_context_service.cc",
     "void ProfileNetworkContextService::DisableQuicIfNotAllowed() {\n"
     "  if (!quic_allowed_.IsManaged()) {\n    return;\n  }\n\n",
     "void ProfileNetworkContextService::DisableQuicIfNotAllowed() {\n"
     "  // Iris: the user's own setting counts, not only policy (Settings ->\n"
     "  // \"Turn off QUIC (HTTP/3)\"; default stays on; apply-privacy-toggles-3.sh).\n\n",
     "the user's own setting counts, not only policy", "QUIC: user setting honoured")

edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  (*s_allowlist)[::prefs::kDisableExtensions] =\n      settings_api::PrefType::kBoolean;\n",
     "  (*s_allowlist)[::prefs::kDisableExtensions] =\n      settings_api::PrefType::kBoolean;\n"
     "  // Iris: apply-privacy-toggles-3.sh\n"
     + "".join("  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % k for k in (FONTS, AUTO, CLIP))
     + "  (*s_allowlist)[::prefs::kEnableReferrers] = settings_api::PrefType::kBoolean;\n"
     + "  (*s_allowlist)[::prefs::kQuicAllowed] = settings_api::PrefType::kBoolean;\n"
     + "".join("  (*s_allowlist)[\"%s%s\"] =\n      settings_api::PrefType::kNumber;\n" % (D, k)
               for k in ("javascript_jit", "subresource_filter", "iris_webgl", "iris_google_signin")),
     "\"%s\"" % FONTS, "allowlist")

# shredding description: clipboard is its own toggle now
edit("chrome/app/settings_strings.grdp",
     "Cookies and site data after 24 hours, cached files after 12 hours, the downloads list after 7 days, and text "
     "copied in Iris from the clipboard after 30 seconds.",
     "Cookies and site data after 24 hours, cached files after 12 hours, and the downloads list after 7 days.",
     "and the downloads list after 7 days.", "shredding sub-label")

def tog(i, key, k, extra=""):
    return ("    <settings-toggle-button id=\"%s\" class=\"hr\"\n"
            "        pref-key=\"%s\"%s\n"
            "        label=\"%s\"\n"
            "        sub-label=\"%s\">\n"
            "    </settings-toggle-button>\n") % (i, key, extra, T[k][0].replace('\\"', "&quot;"),
                                                 T[k][1].replace('\\"', "&quot;"))
NUM = lambda on, off: "\n        numeric-checked-value=\"%d\"\n        numeric-unchecked-values=\"%s\"" % (on, off)
p = "chrome/browser/resources/settings/privacy_page/privacy_page.html"
s = open(p).read()
if "irisBlockWebFontsToggle" in s or moved("irisBlockWebFontsToggle"):
    print("SKIP already applied: %s (toggles)" % p)
else:
    A = "    <settings-toggle-button id=\"irisExtensionsOffToggle\" class=\"hr\"\n"
    i = s.find(A)
    if i < 0 or s.count(A) != 1: die("%s: extensions toggle not found (run apply-privacy-toggles-2.sh first)" % p)
    j = s.find("    </settings-toggle-button>\n", i) + len("    </settings-toggle-button>\n")
    block = ("    <!-- Iris: apply-privacy-toggles-3.sh -->\n"
             + tog("irisBlockAdsToggle", D + "subresource_filter", "ads", NUM(2, "[1, 0]"))
             + tog("irisBlockWebFontsToggle", FONTS, "fonts")
             + tog("irisNoReferrersToggle", "enable_referrers", "ref", "\n        inverted")
             + tog("irisQuicOffToggle", "net.quic_allowed", "quic", "\n        inverted")
             + tog("irisBlockAutoplayToggle", AUTO, "auto")
             + tog("irisClearClipboardToggle", CLIP, "clip")
             + tog("irisWebglAllowToggle", D + "iris_webgl", "gl", NUM(1, "[2, 0]"))
             + tog("irisGoogleSigninToggle", D + "iris_google_signin", "gs", NUM(1, "[2, 0]"))
             + tog("irisJitEverywhereToggle", D + "javascript_jit", "jit", NUM(1, "[2, 0]")))
    open(p, "w").write(s[:j] + block + s[j:]); print("OK   %s : 9 toggles" % p)

# Android
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
CS = "org.chromium.components.content_settings.ContentSetting"
def sw(var, key, title, summary, checked, onchange):
    return ("        ChromeSwitchPreference %s =\n"
            "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
            "        %s.setKey(\"%s\");\n"
            "        %s.setPersistent(false);\n"
            "        %s.setTitle(\"%s\");\n"
            "        %s.setSummary(\n"
            "                \"%s\");\n"
            "        %s.setChecked(%s);\n"
            "        %s.setOnPreferenceChangeListener(\n"
            "                (preference, newValue) -> {\n"
            "                    %s\n"
            "                    return true;\n"
            "                });\n"
            "        irisCategory.addPreference(%s);\n") % (var, var, key, var, var, title, var, summary,
                                                        var, checked, var, onchange, var)
def bool_sw(var, key, k, pref, inverted=False):
    get = "UserPrefs.get(getProfile()).getBoolean(\"%s\")" % pref
    val = "!(Boolean) newValue" if inverted else "(Boolean) newValue"
    return sw(var, key, T[k][0], T[k][1], ("!" + get) if inverted else get,
              "UserPrefs.get(getProfile()).setBoolean(\"%s\", %s);" % (pref, val))
def content_sw(var, key, k, ctype, checked_is):
    other = "ALLOW" if checked_is == "BLOCK" else "BLOCK"
    return sw(var, key, T[k][0], T[k][1],
              "WebsitePreferenceBridge.getDefaultContentSetting(\n                        getProfile(), "
              "ContentSettingsType.%s)\n                == %s.%s" % (ctype, CS, checked_is),
              "WebsitePreferenceBridge.setDefaultContentSetting(\n                            getProfile(),\n"
              "                            ContentSettingsType.%s,\n"
              "                            (Boolean) newValue ? %s.%s : %s.%s);" % (ctype, CS, checked_is, CS, other))
edit(J, "        irisCategory.addPreference(irisClearOnExit);\n",
     "        irisCategory.addPreference(irisClearOnExit);\n"
     "        // Iris: apply-privacy-toggles-3.sh\n"
     + content_sw("irisBlockAds", "iris_block_ads", "ads", "ADS", "BLOCK")
     + bool_sw("irisBlockWebFonts", "iris_block_web_fonts", "fonts", FONTS)
     + bool_sw("irisNoReferrers", "iris_no_referrers", "ref", "enable_referrers", inverted=True)
     + bool_sw("irisQuicOff", "iris_quic_off", "quic", "net.quic_allowed", inverted=True)
     + bool_sw("irisBlockAutoplay", "iris_block_autoplay", "auto", AUTO)
     + bool_sw("irisClearClipboard", "iris_clear_clipboard", "clip", CLIP)
     + content_sw("irisJitEverywhere", "iris_jit_everywhere", "jit", "JAVASCRIPT_JIT", "ALLOW"),
     "irisBlockWebFonts", "Android switches")
edit(J,
     "                \"Every hour: cookies and site data older than 24 hours, cache older than 12 hours,\"\n"
     "                        + \" downloads list older than 7 days. Text copied in Iris is cleared from the\"\n"
     "                        + \" clipboard after 30 seconds.\");\n",
     "                \"Every hour: cookies and site data older than 24 hours, cache older than 12 hours,\"\n"
     "                        + \" downloads list older than 7 days.\");\n",
     "                        + \" downloads list older than 7 days.\");\n", "Android shredding summary")
PY
echo "=== privacy toggles part 3 complete ==="
