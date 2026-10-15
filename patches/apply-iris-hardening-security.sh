#!/usr/bin/env bash
# Iris — Security page folded into "Iris hardening"; Safe Browsing off and hidden (jegly 2026-10-15: "move security into
# iris hardening, so all the options that are in security are toggles under iris hardening"; "remove safe browsing as
# its ineffective as we dont upload to google"; verified against 156.0.8078.11 sources fetched from gitiles — no local
# checkout on the machine that wrote this).
# Desktop Settings -> Privacy and security:
#  1. The "Security" row is hidden (#securityLinkRow, `hidden` so onSecurityPageClick_ stays referenced). The page
#     itself is left in the tree (chrome://settings/security still opens it); nothing in Settings links to it.
#  2. Iris hardening gets a "Security" group first, built from the Security page's own controls:
#       - Always use secure connections: pref-key generated.https_first_mode_enabled, on = ENABLED_FULL (strict, Iris
#         default via apply-phase-a-flips), off = DISABLED; the Balanced/Strict radio pair becomes this one toggle.
#       - Use secure DNS: the upstream <settings-secure-dns> control (toggle + provider list), unchanged.
#       - Strict post-quantum encryption: the toggle apply-strict-pq-tls.sh puts on the Security page, copied from
#         there so its wording stays defined in one place.
#       - Manage security keys (link row, when upstream shows it) + Manage certificates (link row, opens
#         chrome://certificate-manager). Links, not toggles: there is nothing to switch.
#     Not moved: Safe Browsing (removed, see 4), password leak detection (Google's leak-check API: needs sign-in + an
#     API key, so it can't work in Iris either), V8 optimizer link (duplicate of "JIT everywhere"; per-site exceptions
#     stay in Site settings -> JavaScript optimization), Advanced Protection Program (already hidden).
#     Element code: patches/src/.../privacy_page/iris_hardening_page.ts (properties + 2 click handlers + imports).
#  3. route.ts: SECURITY_KEYS becomes a child of IRIS_HARDENING (was SECURITY) so its back arrow returns to Iris
#     hardening. The subpage is mounted with data-parent-view-id="privacy" upstream, so no index change.
# Safe Browsing (desktop + Android):
#  4. prefs::kSafeBrowsingEnabled default true -> false (components/safe_browsing/core/common/safe_browsing_prefs.cc).
#     Iris has no Google API key, so list updates and checks never worked; with every profile off,
#     SafeBrowsingServiceImpl::RefreshState() stops the service (no update attempts to Google at all).
#     Ad blocking is NOT affected: SBLocalDatabaseManager::CheckUrlForSubresourceFilter() returns "no match" at once
#     when no stores are available, and SafeBrowsingPageActivationThrottle then activates from the ALL_SITES config
#     (apply-adblock.sh) — the same path Iris already takes today without an API key.
#     Profiles that explicitly turned Safe Browsing on keep their stored value (a default flip changes defaults only).
#  5. Safety Hub would then show "Safe Browsing is off" in the app menu every 90 days (menu_notification_service.cc,
#     kSafeBrowsingNotificationInterval): SafetyHubSafeBrowsingResult::IsTriggerForMenuNotification() returns false.
#     (Unregistering the module instead would crash OnSafeBrowsingPrefUpdate(), and returning no result would hide
#     every Safety Hub menu notification.)
#  6. Safe Browsing hidden wherever it is still shown (jegly 2026-10-15: "hidden / removed from desktop android"):
#     desktop: the Security page's Safe Browsing section (#safeBrowsingSection, `hidden` so its TS refs stay valid) —
#     the page is unlinked (1) but still opens by URL and still feeds Settings search; Privacy Guide (its other place)
#     is already off (apply-settings-cleanup.sh). Android: Settings -> Privacy and security -> "Safe Browsing" row
#     setVisible(false) right after its setup in onCreatePreferences (the later summary refresh already checks
#     isVisible()), and its settings-search entry is removed instead of having its summary blanked.
# Needs (anchors): apply-iris-hardening-page, apply-strict-pq-tls. Run after apply-security-page-iris.
# STATUS 2026-10-15: copy-tested on upstream 156.0.8078.11 files (+ the anchors the earlier Iris patches create), NOT
#   compile-proven. Prove before any build: settings WebUI (tsc + lint + bundle), safe_browsing_prefs.o,
#   safe_browsing_result.o, chrome_java (PrivacySettings.java).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
R = "chrome/browser/resources/settings/"
SEC = R + "privacy_page/security/security_page.html"

# 1. hide the Security row on Privacy and security
edit(R + "privacy_page/privacy_page.html",
     "    <cr-link-row id=\"securityLinkRow\" start-icon=\"privacy:lock\"\n",
     "    <!-- Iris: Security lives in Iris hardening (apply-iris-hardening-security.sh) -->\n"
     "    <cr-link-row id=\"securityLinkRow\" hidden start-icon=\"privacy:lock\"\n",
     "id=\"securityLinkRow\" hidden", "Security row hidden")
edit(R + "privacy_page/privacy_page.html",
     "        sub-label=\"Ad blocking, JavaScript, WebGL, fonts, timers, cache, clear on exit and more\"\n",
     "        sub-label=\"Secure connections, secure DNS, ad blocking, JavaScript, WebGL, fonts, cache and more\"\n",
     "sub-label=\"Secure connections, secure DNS, ad blocking", "Iris hardening row description")

# 2. Security group on the Iris hardening page
p = R + "privacy_page/iris_hardening_page.html"
s = open(p).read()
if "<h2>Security</h2>" in s:
    print("SKIP already applied: %s (Security group)" % p)
else:
    sec = open(SEC).read()
    m = re.findall(r"    <!-- Iris: strict post-quantum[^\n]*\n"
                   r"    <settings-toggle-button id=\"irisStrictPqTls\"[\s\S]*?</settings-toggle-button>\n", sec)
    if len(m) != 1: die("%s: strict post-quantum toggle not found exactly once (run apply-strict-pq-tls first)" % SEC)
    group = ("  <h2>Security</h2>\n"
             "    <!-- Iris: moved from the Security page (apply-iris-hardening-security.sh) -->\n"
             "    <settings-toggle-button id=\"irisHttpsOnlyToggle\" class=\"hr\"\n"
             "        pref-key=\"generated.https_first_mode_enabled\"\n"
             "        label=\"$i18n{httpsOnlyModeTitle}\"\n"
             "        sub-label=\"$i18n{httpsOnlyModeDescription}\"\n"
             "        numeric-checked-value=\"[[httpsFirstModeChecked_]]\"\n"
             "        numeric-unchecked-values=\"[[httpsFirstModeUncheckedValues_]]\">\n"
             "    </settings-toggle-button>\n"
             "    <template is=\"dom-if\" if=\"[[showSecureDnsSetting_]]\">\n"
             "      <settings-secure-dns class=\"hr\" id=\"irisSecureDns\">\n"
             "      </settings-secure-dns>\n"
             "    </template>\n"
             + m[0] +
             "    <template is=\"dom-if\" if=\"[[enableSecurityKeysSubpage_]]\">\n"
             "      <cr-link-row id=\"securityKeysSubpageTrigger\" class=\"hr\"\n"
             "          label=\"$i18n{securityKeysTitle}\"\n"
             "          sub-label=\"$i18n{securityKeysDesc}\"\n"
             "          on-click=\"onSecurityKeysClick_\"\n"
             "          role-description=\"$i18n{subpageArrowRoleDescription}\">\n"
             "      </cr-link-row>\n"
             "    </template>\n"
             "    <cr-link-row id=\"manageCertificatesLinkRow\" class=\"hr\"\n"
             "        label=\"$i18n{manageCertificates}\"\n"
             "        sub-label=\"$i18n{manageCertificatesDescription}\"\n"
             "        on-click=\"onManageCertificatesClick_\" external>\n"
             "    </cr-link-row>\n")
    edit(p, "  <h2>Ads and trackers</h2>\n", group + "  <h2>Ads and trackers</h2>\n",
         "<h2>Security</h2>", "Security group")

# 3. security keys subpage: back arrow -> Iris hardening
edit(R + "route.ts",
     "    r.SECURITY_KEYS = r.SECURITY.createChild('/securityKeys');\n",
     "    // Iris: parent is Iris hardening (apply-iris-hardening-security.sh)\n"
     "    r.SECURITY_KEYS = r.IRIS_HARDENING.createChild('/securityKeys');\n",
     "r.SECURITY_KEYS = r.IRIS_HARDENING.createChild", "security keys route parent")

# 4. Safe Browsing off by default
edit("components/safe_browsing/core/common/safe_browsing_prefs.cc",
     "  registry->RegisterBooleanPref(\n"
     "      prefs::kSafeBrowsingEnabled, true,\n"
     "      user_prefs::PrefRegistrySyncable::SYNCABLE_PREF);\n",
     "  // Iris: off by default — no Google API key, so Safe Browsing can't work\n"
     "  // (apply-iris-hardening-security.sh).\n"
     "  registry->RegisterBooleanPref(\n"
     "      prefs::kSafeBrowsingEnabled, false,\n"
     "      user_prefs::PrefRegistrySyncable::SYNCABLE_PREF);\n",
     "prefs::kSafeBrowsingEnabled, false,", "Safe Browsing default off")

# 5. no "Safe Browsing is off" menu notification
edit("chrome/browser/ui/safety_hub/safe_browsing_result.cc",
     "bool SafetyHubSafeBrowsingResult::IsTriggerForMenuNotification() const {\n"
     "  return status_ == SafeBrowsingState::kDisabledByUser;\n"
     "}\n",
     "bool SafetyHubSafeBrowsingResult::IsTriggerForMenuNotification() const {\n"
     "  // Iris: Safe Browsing is off on purpose (apply-iris-hardening-security.sh).\n"
     "  return false;\n"
     "}\n",
     "Safe Browsing is off on purpose (apply-iris-hardening-security.sh)", "no Safe Browsing menu nag")

# 6. Safe Browsing hidden: desktop Security page section; Android row + settings-search entry
edit(SEC, "    <div id=\"safeBrowsingSection\">\n",
     "    <!-- Iris: no Safe Browsing (apply-iris-hardening-security.sh) -->\n"
     "    <div id=\"safeBrowsingSection\" hidden>\n",
     "<div id=\"safeBrowsingSection\" hidden>", "desktop Safe Browsing section hidden")
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
edit(J, "                                    SettingsAccessPoint.PARENT_SETTINGS);\n"
        "                    return false;\n"
        "                });\n",
     "                                    SettingsAccessPoint.PARENT_SETTINGS);\n"
     "                    return false;\n"
     "                });\n"
     "        // Iris: no Safe Browsing (apply-iris-hardening-security.sh).\n"
     "        safeBrowsingPreference.setVisible(false);\n",
     "safeBrowsingPreference.setVisible(false);", "Android Safe Browsing row hidden")
edit(J, "                    // The summary in 'Safe Browsing' is a template string. Removes it.\n"
        "                    indexData.updateEntrySummaryForKey(\n"
        "                            frag, PREF_SAFE_BROWSING, /* summaryId= */ 0);\n",
     "                    // Iris: no Safe Browsing (apply-iris-hardening-security.sh).\n"
     "                    indexData.removeEntry(getUniqueId(PREF_SAFE_BROWSING));\n",
     "indexData.removeEntry(getUniqueId(PREF_SAFE_BROWSING));", "Android Safe Browsing search entry")
PY
echo "=== Iris hardening: Security group + Safe Browsing off and hidden complete ==="
