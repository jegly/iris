#!/usr/bin/env bash
# Iris — origin trials OFF (jegly 2026-09-26; verified against checkout 2026-09-26).
# WHY: an origin-trial token lets a site re-enable, on its own pages, experimental features Iris cut (e.g.
# AdInterestGroupAPI / Protected Audience, AIWriterAPI, AIRewriterAPI): generated XEnabled(context) falls back to
# context->FeatureEnabled(OriginTrialFeature::kX) when the runtime flag is off (runtime_enabled_features.cc.tmpl).
# NOT --disable-origin-trial-controlled-blink-features: that only clears the BASE flags of OT-controlled features
# (it can switch off stable ones) and tokens still enable them per page.
# MECHANISM: embedder_support::OriginTrialPolicyImpl::IsOriginTrialsSupported() (used by Chrome AND WebView via
# ChromeContentClient / AwContentClient) returns false -> blink::TrialTokenValidator rejects every token
# (OriginTrialTokenStatus::kNotSupported) in browser and renderer; deprecation trials are off too.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "components/embedder_support/origin_trials/origin_trial_policy_impl.cc"
s = open(p).read()
old = "bool OriginTrialPolicyImpl::IsOriginTrialsSupported() const {\n  return true;\n}"
new = ("bool OriginTrialPolicyImpl::IsOriginTrialsSupported() const {\n"
       "  // Iris: no origin trials; tokens cannot re-enable features Iris disables.\n"
       "  return false;\n}")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: sys.stderr.write(f"ERROR: {p}: IsOriginTrialsSupported body changed (drift?)\n"); sys.exit(1)
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : origin trials disabled")
v = open("third_party/blink/common/origin_trials/trial_token_validator.cc").read()
if v.count("!policy->IsOriginTrialsSupported()") < 2:
    sys.stderr.write("ERROR: TrialTokenValidator no longer gates on IsOriginTrialsSupported()\n"); sys.exit(1)
print("OK   guard: TrialTokenValidator gates on IsOriginTrialsSupported()")
PY
echo "=== origin trials off complete ==="
