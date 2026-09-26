#!/usr/bin/env bash
# Iris — no enterprise / MDM policy (jegly 2026-09-26: "no kerberos or weird remote capabilities / MDM").
# Verified against this checkout 2026-09-26.
# WHY: ChromeBrowserPolicyConnector::CreatePlatformProvider() (chrome/browser/policy/chrome_browser_policy_connector.cc)
#   loads admin policies from the platform, at the HIGHEST priority:
#   - Linux: ConfigDirPolicyLoader on chrome::DIR_POLICY_FILES = /etc/chromium/policies (policy_paths.cc:21). Anything
#     with root — or a distro Chromium package's policy files, which use the same path — could silently reconfigure
#     Iris (turn the network sandbox back off, force-install extensions, change DNS, ...).
#   - Android: AndroidCombinedPolicyProvider = MDM "app restrictions" (Android Enterprise / EMM).
# CHANGE: both branches return nullptr. The caller (CreatePolicyProviders) already handles a null provider.
#   Bodies are replaced (not an early return) so no unreachable code (-Wunreachable-code-aggressive).
# Already off without a patch: Chrome Browser Cloud Management (remote enrollment) — unbranded builds only enable it
#   with --enable-chrome-browser-cloud-management (components/enterprise/browser/controller/
#   chrome_browser_cloud_management_controller.cc:102). Kerberos + enterprise_* features: gn args (research B13 batch).
# Windows/Mac branches untouched (not Iris targets). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/policy/chrome_browser_policy_connector.cc"
s = open(p).read()
marker = "// Iris: no platform (admin/MDM) policies"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
linux_old = ("#elif BUILDFLAG(IS_POSIX) && !BUILDFLAG(IS_ANDROID) && !BUILDFLAG(IS_CHROMEOS)\n"
             "  base::FilePath config_dir_path;\n"
             "  if (base::PathService::Get(chrome::DIR_POLICY_FILES, &config_dir_path)) {\n"
             "    auto loader = std::make_unique<ConfigDirPolicyLoader>(\n"
             "        base::ThreadPool::CreateSequencedTaskRunner(\n"
             "            {base::MayBlock(), base::TaskPriority::BEST_EFFORT}),\n"
             "        config_dir_path, POLICY_SCOPE_MACHINE);\n"
             "    return std::make_unique<AsyncPolicyProvider>(GetSchemaRegistry(),\n"
             "                                                 std::move(loader));\n"
             "  } else {\n"
             "    return nullptr;\n"
             "  }\n"
             "#elif BUILDFLAG(IS_ANDROID)\n"
             "  return std::make_unique<android::AndroidCombinedPolicyProvider>(\n"
             "      GetSchemaRegistry());\n")
linux_new = ("#elif BUILDFLAG(IS_POSIX) && !BUILDFLAG(IS_ANDROID) && !BUILDFLAG(IS_CHROMEOS)\n"
             "  " + marker + " from /etc/chromium/policies: nothing outside the\n"
             "  // browser can reconfigure it.\n"
             "  return nullptr;\n"
             "#elif BUILDFLAG(IS_ANDROID)\n"
             "  // Iris: no MDM app-restriction policies.\n"
             "  return nullptr;\n")
if s.count(linux_old) != 1: die(f"{p}: CreatePlatformProvider Linux/Android branches changed (drift?)")
open(p, "w").write(s.replace(linux_old, linux_new)); print("OK   " + p + " : no platform policy provider (Linux, Android)")
s = open(p).read()
if "if (platform_provider) {" not in s: die("CreatePolicyProviders no longer tolerates a null platform provider")
print("OK   guard: caller handles a null platform provider")
PY
echo "=== no platform (admin/MDM) policy complete ==="
