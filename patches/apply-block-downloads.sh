#!/usr/bin/env bash
# Iris — "Block all downloads" switch (jegly 2026-10-09; idea from his www browser; verified against 156.0.8078.11).
# Profile pref iris.privacy.block_downloads (registered in iris_shredder.cc), OFF by default. When on,
# ChromeDownloadManagerDelegate::CheckDownloadAllowed() refuses every download before it starts. That function is the
# gate DownloadManagerImpl uses for navigations that turn into downloads (content/browser/download/
# download_manager_impl.cc, ~1225) and for DownloadUrl() calls (~1938), and it is shared by desktop and Android.
# The refusal is silent (nothing is saved, no download appears). Not covered: "Save page as" / printing to PDF, which
# write files without the download manager's network path.
# Desktop: Settings -> Privacy and security -> Iris hardening -> Data. Android: Privacy and security -> Data group.
# Needs apply-shredder, apply-iris-hardening-page, apply-android-iris-privacy-settings.
# STATUS 2026-10-09: copy-tested only, NOT compile-proven.
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
KEY = "iris.privacy.block_downloads"
TITLE = "Block all downloads"
SUB = ("Iris refuses every file download, including ones you start yourself. Nothing is saved to your device. "
       "Turn it off when you need to download a file.")
edit("chrome/browser/download/chrome_download_manager_delegate.cc",
     "  DCHECK_CURRENTLY_ON(BrowserThread::UI);\n"
     "#if BUILDFLAG(IS_WIN) || BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS) || \\\n"
     "    BUILDFLAG(IS_MAC)\n"
     "  // Don't download pdf if it is a file URL",
     "  DCHECK_CURRENTLY_ON(BrowserThread::UI);\n"
     "  // Iris: Settings -> \"Block all downloads\" (apply-block-downloads.sh).\n"
     "  if (profile_->GetPrefs()->GetBoolean(\"%s\")) {\n"
     "    OnCheckDownloadAllowedFailed(std::move(check_download_allowed_cb));\n"
     "    return;\n"
     "  }\n"
     "#if BUILDFLAG(IS_WIN) || BUILDFLAG(IS_LINUX) || BUILDFLAG(IS_CHROMEOS) || \\\n"
     "    BUILDFLAG(IS_MAC)\n"
     "  // Don't download pdf if it is a file URL" % KEY,
     "\"%s\"" % KEY, "download gate")
edit("chrome/browser/extensions/api/settings_private/prefs_util.cc",
     "  // Iris: apply-privacy-toggles-3.sh\n",
     "  // Iris: apply-privacy-toggles-3.sh\n"
     "  (*s_allowlist)[\"%s\"] = settings_api::PrefType::kBoolean;\n" % KEY,
     "\"%s\"" % KEY, "allowlist")
H = "chrome/browser/resources/settings/privacy_page/iris_hardening_page.html"
edit(H, "  <h2>Address bar</h2>\n",
     "  <settings-toggle-button id=\"irisBlockDownloadsToggle\" class=\"hr\"\n"
     "      pref-key=\"%s\"\n"
     "      label=\"%s\"\n"
     "      sub-label=\"%s\">\n"
     "  </settings-toggle-button>\n"
     "  <h2>Address bar</h2>\n" % (KEY, TITLE, SUB),
     "irisBlockDownloadsToggle", "desktop toggle")
J = "chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettings.java"
sw = ("        ChromeSwitchPreference irisBlockDownloads =\n"
      "                new ChromeSwitchPreference(getPreferenceManager().getContext());\n"
      "        irisBlockDownloads.setKey(\"iris_block_downloads\");\n"
      "        irisBlockDownloads.setPersistent(false);\n"
      "        irisBlockDownloads.setTitle(\"%s\");\n"
      "        irisBlockDownloads.setSummary(\n"
      "                \"%s\");\n"
      "        irisBlockDownloads.setChecked(\n"
      "                UserPrefs.get(getProfile()).getBoolean(\"%s\"));\n"
      "        irisBlockDownloads.setOnPreferenceChangeListener(\n"
      "                (preference, newValue) -> {\n"
      "                    UserPrefs.get(getProfile()).setBoolean(\"%s\", (Boolean) newValue);\n"
      "                    return true;\n"
      "                });\n"
      "        irisCategory.addPreference(irisBlockDownloads);\n") % (TITLE, SUB, KEY, KEY)
edit(J, "        irisCategory.addPreference(irisJitEverywhere);\n",
     sw + "        irisCategory.addPreference(irisJitEverywhere);\n",
     "irisBlockDownloads =", "Android switch")
edit(J, '"iris_clear_clipboard", "iris_download_ask"}',
     '"iris_clear_clipboard", "iris_download_ask", "iris_block_downloads"}',
     '"iris_block_downloads"}', "Android group")
PY
echo "=== block downloads complete ==="
