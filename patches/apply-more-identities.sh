#!/usr/bin/env bash
# Iris — more browser identities: 4 -> 14 entries (jegly 2026-10-06: "none for android, only four, not enough").
# The identity list lives in patches/src/chrome/browser/iris/iris_user_agent.cc (13 presets: Firefox on Linux/Windows/
# macOS/Android, Chrome on Windows/macOS/Linux/Android/iPhone, Edge on Windows, Safari on macOS/iPhone, Samsung
# Internet on Android); apply-user-agent.sh copies it into the tree (re-run it, or apply-all, after editing). This
# script adds the new entries to the three menus that were hard-coded to the first four, with plain English labels
# (no new grit strings), and teaches navigator.platform / vendor about the new identities:
#  - desktop Settings -> Site settings -> a site -> "Browser identity" (site_details.html select)
#  - desktop Page Info -> "Browser identity" quick menu (page_info_main_view.cc table: new entries carry an English
#    label instead of a string id)
#  - Android Site settings -> the site -> Browser identity (SingleWebsiteSettings.java arrays)
#  - navigator.platform: iPhone identity -> "iPhone", Android identities -> "Linux armv81" (Windows/Mac unchanged);
#    navigator.vendor: iPhone identities (Safari and Chrome on iOS) -> "Apple Computer, Inc."
# Not covered (needs engine changes): Firefox's navigator.oscpu/buildID, window.chrome, touch points / screen size,
# TLS fingerprint. A mobile identity on a desktop (or a desktop one on a phone) therefore still differs in those.
# Needs apply-user-agent.sh, apply-page-info-identity.sh, apply-android-per-site.sh, apply-ua-navigator-consistency.sh.
# STATUS 2026-10-06: copy-tested only, NOT compile-proven (page_info_main_view.o, iris_user_agent.o, navigator*.o,
# chrome_java, settings WebUI).
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

# (id, label), in menu order (after the default entry)
IDS = [("firefox_linux", "Firefox on Linux"), ("firefox_windows", "Firefox on Windows"),
       ("firefox_mac", "Firefox on macOS"), ("firefox_android", "Firefox on Android"),
       ("chrome_windows", "Chrome on Windows"), ("chrome_mac", "Chrome on macOS"),
       ("chrome_linux", "Chrome on Linux"), ("chrome_android", "Chrome on Android"),
       ("chrome_ios", "Chrome on iPhone"), ("edge_windows", "Edge on Windows"),
       ("safari_mac", "Safari on macOS"), ("safari_ios", "Safari on iPhone"),
       ("samsung_android", "Samsung Internet on Android")]
OLD3 = {"firefox_linux", "chrome_windows", "safari_mac"}
NEW = [(i, l) for i, l in IDS if i not in OLD3]

# 1. desktop Settings select
edit("chrome/browser/resources/settings/site_settings/site_details.html",
     "          <option value=\"safari_mac\" selected=\"[[isIrisUserAgent_(irisUserAgent_, 'safari_mac')]]\">$i18n{irisUserAgentSafariMac}</option>\n",
     "          <option value=\"safari_mac\" selected=\"[[isIrisUserAgent_(irisUserAgent_, 'safari_mac')]]\">$i18n{irisUserAgentSafariMac}</option>\n" +
     "".join("          <option value=\"%s\" selected=\"[[isIrisUserAgent_(irisUserAgent_, '%s')]]\">%s</option>\n" % (i, i, l)
             for i, l in NEW),
     'value="samsung_android"', "Settings identity list")

# 2. desktop Page Info menu
p = "chrome/browser/ui/views/page_info/page_info_main_view.cc"
edit(p,
     "struct IrisIdentityPreset {\n  const char* id;\n  int label_id;\n};\n",
     "struct IrisIdentityPreset {\n  const char* id;\n  int label_id;           // string id, or 0\n"
     "  const char16_t* label;  // English label when label_id is 0\n};\n"
     "std::u16string IrisIdentityLabel(const IrisIdentityPreset& preset) {\n"
     "  return preset.label_id ? l10n_util::GetStringUTF16(preset.label_id)\n"
     "                         : std::u16string(preset.label);\n}\n",
     "IrisIdentityLabel", "Page Info struct + label helper")
rows = ['    {"", IDS_SETTINGS_IRIS_USER_AGENT_DEFAULT, nullptr},\n']
for i, l in IDS:
    sid = {"firefox_linux": "IDS_SETTINGS_IRIS_USER_AGENT_FIREFOX_LINUX",
           "chrome_windows": "IDS_SETTINGS_IRIS_USER_AGENT_CHROME_WINDOWS",
           "safari_mac": "IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC"}.get(i)
    rows.append('    {"%s", %s, nullptr},\n' % (i, sid) if sid else '    {"%s", 0, u"%s"},\n' % (i, l))
edit(p,
     '    {"", IDS_SETTINGS_IRIS_USER_AGENT_DEFAULT},\n'
     '    {"firefox_linux", IDS_SETTINGS_IRIS_USER_AGENT_FIREFOX_LINUX},\n'
     '    {"chrome_windows", IDS_SETTINGS_IRIS_USER_AGENT_CHROME_WINDOWS},\n'
     '    {"safari_mac", IDS_SETTINGS_IRIS_USER_AGENT_SAFARI_MAC},\n',
     "".join(rows), 'u"Samsung Internet on Android"', "Page Info table")
edit(p,
     "      menu_model_.AddRadioItemWithStringId(command_id++, preset.label_id, 0);\n",
     "      menu_model_.AddRadioItem(command_id++, IrisIdentityLabel(preset), 0);\n",
     "AddRadioItem(command_id++, IrisIdentityLabel(preset)", "Page Info menu items")
edit(p,
     "        SetSubtitleText(l10n_util::GetStringUTF16(preset.label_id));\n",
     "        SetSubtitleText(IrisIdentityLabel(preset));\n",
     "SetSubtitleText(IrisIdentityLabel(preset))", "Page Info subtitle")

# 3. Android Site settings
edit("components/browser_ui/site_settings/android/java/src/org/chromium/components/browser_ui/site_settings/SingleWebsiteSettings.java",
     '                        new String[] {\n'
     '                            "Iris (default)", "Firefox on Linux", "Chrome on Windows", "Safari on macOS"\n'
     '                        },\n'
     '                        new String[] {"", "firefox_linux", "chrome_windows", "safari_mac"},\n',
     '                        new String[] {\n'
     '                            "Iris (default)",\n' +
     "".join('                            "%s",\n' % l for i, l in IDS) +
     '                        },\n'
     '                        new String[] {\n'
     '                            "",\n' +
     "".join('                            "%s",\n' % i for i, l in IDS) +
     '                        },\n',
     '"samsung_android",', "Android identity list")

# 4. navigator.platform / vendor
edit("third_party/blink/renderer/core/execution_context/navigator_base.cc",
     "  if (iris_user_agent.contains(\"Macintosh\")) {\n    return \"MacIntel\";\n  }\n",
     "  if (iris_user_agent.contains(\"Macintosh\")) {\n    return \"MacIntel\";\n  }\n"
     "  if (iris_user_agent.contains(\"iPhone\")) {\n    return \"iPhone\";\n  }\n"
     "  if (iris_user_agent.contains(\"Android\")) {\n    return \"Linux armv81\";\n  }\n",
     'iris_user_agent.contains("iPhone")) {\n    return "iPhone";', "platform: iPhone / Android")
edit("third_party/blink/renderer/core/frame/navigator.cc",
     "  if (iris_user_agent.contains(\"Safari/\") &&\n"
     "      iris_user_agent.contains(\"Version/\") &&\n"
     "      !iris_user_agent.contains(\"Chrome/\")) {\n"
     "    return \"Apple Computer, Inc.\";\n  }\n",
     "  if (iris_user_agent.contains(\"iPhone\") ||\n"
     "      (iris_user_agent.contains(\"Safari/\") &&\n"
     "       iris_user_agent.contains(\"Version/\") &&\n"
     "       !iris_user_agent.contains(\"Chrome/\"))) {\n"
     "    return \"Apple Computer, Inc.\";\n  }\n",
     'iris_user_agent.contains("iPhone") ||', "vendor: iPhone")
PY
echo "=== more browser identities complete ==="
