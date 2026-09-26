#!/usr/bin/env bash
# Iris — Global Privacy Control ON for every site (final-release roadmap; verified against checkout 2026-09-26).
# GPC = the legal "do not sell or share my data" signal: `Sec-GPC: 1` request header + navigator.globalPrivacyControl.
# MECHANISM (upstream plumbing already exists, gated off):
# - blink::IsGlobalPrivacyControlFeatureAndSettingEnabled() (third_party/blink/common/global_privacy_control/) returns
#   true whenever base::Feature "GlobalPrivacyControlForce" is enabled. It is consulted for frame navigations
#   (content/renderer/render_frame_impl.cc), browser-initiated requests (content/browser/loader/
#   browser_initiated_resource_request.cc), subresources and workers (service worker + dedicated/shared worker fetch
#   contexts) and navigator.globalPrivacyControl (modules/global_privacy_control/).
# - The feature is auto-generated from runtime_enabled_features.json5 ("GlobalPrivacyControlForce", default DISABLED);
#   the Blink runtime flag "GlobalPrivacyControl" is implied_by it (copied from the base::Feature because it is overridden).
# - Enabled by adding it to --enable-features in the browser process, inside the Iris compiled-in switches block
#   (apply-default-switches.sh). NOT a json5 edit: that would force another large Blink rebuild. The browser forwards
#   feature overrides to child processes.
# - base::FeatureList reads ONE --enable-features value (the last), so the existing value is MERGED, never replaced:
#   a user's own --enable-features keeps working.
# Needs apply-default-switches.sh first (anchors on its block). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/app/chrome_main_delegate.cc"
s = open(p).read()
marker = "// Iris: Global Privacy Control"
if marker in s: print("SKIP already applied: " + p); sys.exit(0)
anchor = "    iris_command_line->AppendSwitch(switches::kDisableBackgroundNetworking);\n"
if s.count(anchor) != 1: die(f"{p}: Iris switches block not found (run apply-default-switches.sh first)")
if '#include "base/base_switches.h"' not in s: die(f"{p}: base/base_switches.h no longer included")
block = (anchor +
  "    // Iris: Global Privacy Control (Sec-GPC: 1 + navigator.globalPrivacyControl)\n"
  "    // on every site. Merged into any existing --enable-features value, which\n"
  "    // base::FeatureList reads as a single switch.\n"
  "    {\n"
  "      std::string iris_features =\n"
  "          iris_command_line->GetSwitchValueASCII(switches::kEnableFeatures);\n"
  "      if (!iris_features.empty()) {\n"
  "        iris_features += \",\";\n"
  "      }\n"
  "      iris_features += \"GlobalPrivacyControlForce\";\n"
  "      iris_command_line->AppendSwitchASCII(switches::kEnableFeatures,\n"
  "                                           iris_features);\n"
  "    }\n")
open(p, "w").write(s.replace(anchor, block, 1)); print("OK   " + p + " : Global Privacy Control on")

# guards: the upstream gate still keys off the Force feature, and the generated feature name is unchanged
g = open("third_party/blink/common/global_privacy_control/global_privacy_control_util.cc").read()
if "features::kGlobalPrivacyControlForce" not in g: die("GPC gate no longer uses kGlobalPrivacyControlForce")
j = open("third_party/blink/renderer/platform/runtime_enabled_features.json5").read()
if 'name: "GlobalPrivacyControlForce",' not in j: die("json5 no longer defines GlobalPrivacyControlForce")
print("OK   guard: GPC gate + generated feature name unchanged")
PY
echo "=== Global Privacy Control on complete ==="
