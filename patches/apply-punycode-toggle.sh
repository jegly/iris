#!/usr/bin/env bash
# Iris — "Show web addresses as punycode", off by default (issue #1 item 8, jegly 2026-11-05).
# Verified against 157.0.8103.38: every place that DISPLAYS a host (omnibox, page info, tab hover cards, downloads,
# history, Android URL bar...) converts xn-- labels through url_formatter's IDNToUnicodeOneComponent(); when the
# setting is on, that function leaves the label in punycode. Only for display: callers that ignore spoof-check
# results (UnsafeIDNToUnicode*, which the lookalike-domain warning uses) still decode, so that warning keeps working.
# Pref: browser-wide Local State "iris.ui.always_punycode" (registered + observed in BrowserProcessImpl like
# iris.adblock.extra), pushed into url_formatter at start and on every change (a std::atomic<bool>; addresses shown
# after the switch use the new form).
# UI: desktop Settings -> Privacy and security -> Iris hardening -> Address bar; Android Settings -> Privacy and
# security -> Iris (LocalStatePrefs, like strict post-quantum). English-only labels (no grit rebuild).
# Needs (anchors): apply-adblock-extra, apply-iris-hardening-page, apply-strict-pq-tls, apply-privacy-toggles-3.
# STATUS 2026-11-05: copy-tested on 157 file copies, NOT compile-proven.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
PREF = "iris.ui.always_punycode"
LABEL = "Show web addresses as punycode"
SUB = ("Domain names with non-Latin or accented letters are shown in their xn-- form, so a lookalike letter "
       "can't pass for a familiar site. Such names become hard to read.")

# 1. url_formatter: the switch + its use
H = "components/url_formatter/url_formatter.h"
edit(H, "std::u16string IDNToUnicode(std::string_view host);\n",
     "std::u16string IDNToUnicode(std::string_view host);\n\n"
     "// Iris: when true, IDN labels are displayed as punycode (xn--...); callers that\n"
     "// ignore spoof-check results still get Unicode (apply-punycode-toggle.sh).\n"
     "void SetIrisAlwaysShowPunycode(bool on);\n",
     "SetIrisAlwaysShowPunycode", "declaration")
C = "components/url_formatter/url_formatter.cc"
edit(C, "#include <algorithm>\n", "#include <algorithm>\n#include <atomic>  // Iris\n",
     "#include <atomic>  // Iris", "include")
edit(C, "const char kMobilePrefix[] = \"m.\";\nconstexpr size_t kMobilePrefixLength = 2;\n",
     "const char kMobilePrefix[] = \"m.\";\nconstexpr size_t kMobilePrefixLength = 2;\n\n"
     "// Iris: Settings -> \"Show web addresses as punycode\" (apply-punycode-toggle.sh).\n"
     "std::atomic<bool> g_iris_always_punycode{false};\n",
     "g_iris_always_punycode{false}", "flag")
edit(C, "  static constexpr char16_t kIdnPrefix[] = u\"xn--\";\n"
        "  if (!base::StartsWith(comp, kIdnPrefix) || comp.back() == '-') {\n"
        "    out->append(comp);\n"
        "    return result;\n"
        "  }\n",
     "  static constexpr char16_t kIdnPrefix[] = u\"xn--\";\n"
     "  if (!base::StartsWith(comp, kIdnPrefix) || comp.back() == '-') {\n"
     "    out->append(comp);\n"
     "    return result;\n"
     "  }\n\n"
     "  // Iris: keep punycode for display when the setting is on. Lookalike checks\n"
     "  // (ignore_spoof_check_results) still decode.\n"
     "  if (!ignore_spoof_check_results &&\n"
     "      g_iris_always_punycode.load(std::memory_order_relaxed)) {\n"
     "    out->append(comp);\n"
     "    return result;\n"
     "  }\n",
     "g_iris_always_punycode.load(", "display keeps punycode")
edit(C, "std::u16string MaybeRemoveDiacritics(const std::u16string& host) {\n"
        "  return GetIDNSpoofChecker().MaybeRemoveDiacritics(host);\n}\n",
     "std::u16string MaybeRemoveDiacritics(const std::u16string& host) {\n"
     "  return GetIDNSpoofChecker().MaybeRemoveDiacritics(host);\n}\n\n"
     "void SetIrisAlwaysShowPunycode(bool on) {  // Iris\n"
     "  g_iris_always_punycode.store(on, std::memory_order_relaxed);\n}\n",
     "void SetIrisAlwaysShowPunycode(bool on) {", "setter")

# 2. browser: Local State pref, applied at start and on change
B = "chrome/browser/browser_process_impl.cc"
edit(B, '#include "components/subresource_filter/content/browser/ruleset_service.h"\n',
     '#include "components/subresource_filter/content/browser/ruleset_service.h"\n'
     '#include "components/url_formatter/url_formatter.h"  // Iris (punycode)\n',
     '#include "components/url_formatter/url_formatter.h"  // Iris (punycode)', "include")
edit(B, 'const char kIrisAdblockExtraPref[] = "iris.adblock.extra";\n',
     'const char kIrisAdblockExtraPref[] = "iris.adblock.extra";\n'
     '// Iris: Settings -> "Show web addresses as punycode" (apply-punycode-toggle.sh).\n'
     'const char kIrisPunycodePref[] = "%s";\n' % PREF,
     "kIrisPunycodePref[]", "pref name")
edit(B, "  registry->RegisterBooleanPref(kIrisAdblockExtraPref, false);\n",
     "  registry->RegisterBooleanPref(kIrisAdblockExtraPref, false);\n"
     "  registry->RegisterBooleanPref(kIrisPunycodePref, false);  // Iris\n",
     "RegisterBooleanPref(kIrisPunycodePref", "register pref")
edit(B, "          base::Unretained(this)));\n\n"
        "#if BUILDFLAG(IS_ANDROID)\n"
        "  chrome_browser_prefs::OnLocalStatePrefsLoaded();\n",
     "          base::Unretained(this)));\n"
     "  // Iris: \"Show web addresses as punycode\" (apply-punycode-toggle.sh).\n"
     "  url_formatter::SetIrisAlwaysShowPunycode(\n"
     "      local_state()->GetBoolean(kIrisPunycodePref));\n"
     "  pref_change_registrar_.Add(\n"
     "      kIrisPunycodePref,\n"
     "      base::BindRepeating(\n"
     "          [](BrowserProcessImpl* self) {\n"
     "            url_formatter::SetIrisAlwaysShowPunycode(\n"
     "                self->local_state()->GetBoolean(kIrisPunycodePref));\n"
     "          },\n"
     "          base::Unretained(this)));\n\n"
     "#if BUILDFLAG(IS_ANDROID)\n"
     "  chrome_browser_prefs::OnLocalStatePrefsLoaded();\n",
     "SetIrisAlwaysShowPunycode(\n      local_state()", "apply at start + on change")

# 3. Settings may read/write it
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % PREF,
     "\"%s\"" % PREF, "allowlist")

# 4. desktop toggle, end of the Address bar group (last group on the page)
edit("chrome/browser/resources/settings/privacy_page/iris_hardening_page.html",
     "</settings-subpage>\n",
     "    <settings-toggle-button id=\"irisPunycodeToggle\" class=\"hr\"\n"
     "        pref-key=\"%s\"\n"
     "        label=\"%s\"\n"
     "        sub-label=\"%s\">\n"
     "    </settings-toggle-button>\n"
     "</settings-subpage>\n" % (PREF, LABEL, SUB.replace("'", "&#39;")),
     "irisPunycodeToggle", "desktop toggle")

# 5. Android switch (Local State), next to strict post-quantum
edit("chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java",
     "        irisCategory.addPreference(irisStrictPqTls);\n",
     "        irisCategory.addPreference(irisStrictPqTls);\n"
     "        // Iris: \"Show web addresses as punycode\" (browser-wide Local State pref).\n"
     "        ChromeSwitchPreference irisPunycode =\n"
     "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
     "        irisPunycode.setKey(\"iris_punycode\");\n"
     "        irisPunycode.setPersistent(false);\n"
     "        irisPunycode.setTitle(\"%s\");\n"
     "        irisPunycode.setSummary(\n"
     "                \"%s\");\n"
     "        irisPunycode.setEnabled(irisLocalState != null);\n"
     "        irisPunycode.setChecked(\n"
     "                irisLocalState != null && irisLocalState.getBoolean(\"%s\"));\n"
     "        irisPunycode.setOnPreferenceChangeListener(\n"
     "                (preference, newValue) -> {\n"
     "                    org.chromium.components.prefs.PrefService localState =\n"
     "                            org.chromium.chrome.browser.prefs.LocalStatePrefs.get();\n"
     "                    if (localState == null) return false;\n"
     "                    localState.setBoolean(\"%s\", (Boolean) newValue);\n"
     "                    return true;\n"
     "                });\n"
     "        irisCategory.addPreference(irisPunycode);\n" % (LABEL, SUB, PREF, PREF),
     "irisPunycode", "Android switch")
PY
echo "=== punycode toggle complete ==="
