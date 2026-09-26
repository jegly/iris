#!/usr/bin/env bash
# Iris — sandbox the network service on Linux (hardening checklist review 2026-09-26; verified against this checkout).
# WHY: the network service parses everything that arrives from the internet (HTTP, TLS, DNS, cookies, cache) and on Linux
#   it runs UNSANDBOXED by default: sandbox/policy/features.cc kNetworkServiceSandbox = DISABLED (Mac/Fuchsia always on).
# MECHANISM (upstream, finished for Linux):
# - Enabling kNetworkServiceSandbox makes IsNetworkSandboxEnabled() true (sandbox/policy/features.cc:166); Chrome then
#   launches the service sandboxed (chrome/browser/net/system_network_context_manager.cc:1075; a configured Kerberos
#   setup or the NetworkServiceSandboxEnabled policy still turns it off, as upstream intends).
# - Linux policy: seccomp-BPF (sandbox/policy/linux/bpf_network_policy_linux.cc) + a syscall broker whose file allowlist
#   (services/network/network_sandbox_hook_linux.cc) permits only the resolver config files in /etc and read/write to the
#   profile's network-data directories. kNetworkServiceSyscallFilter + kNetworkServiceFileAllowlist are ENABLED upstream.
# - No data migration on Linux (kTriggerNetworkDataMigration is Windows-only) -> cookies stay where they are.
# LINUX ONLY: Android's process model differs; not enabled there.
# RUNTIME TEST REQUIRED before calling this done: browsing, downloads, cookies survive restart, DoH + system DNS,
#   chrome://sandbox shows the network service sandboxed. Possible loss: client certificates / CAs added to the NSS DB
#   (~/.pki/nssdb) if the sandbox hides it (WebAuthn/YubiKey logins are browser-side and unaffected).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "sandbox/policy/features.cc"
s = open(p).read()
old = ("// Enables network service sandbox.\n"
       "// (Only causes an effect when feature kNetworkServiceInProcess is disabled.)\n"
       "BASE_FEATURE(kNetworkServiceSandbox, base::FEATURE_DISABLED_BY_DEFAULT);\n")
new = ("// Enables network service sandbox.\n"
       "// (Only causes an effect when feature kNetworkServiceInProcess is disabled.)\n"
       "// Iris: on by default on Linux.\n"
       "#if BUILDFLAG(IS_LINUX)\n"
       "BASE_FEATURE(kNetworkServiceSandbox, base::FEATURE_ENABLED_BY_DEFAULT);\n"
       "#else\n"
       "BASE_FEATURE(kNetworkServiceSandbox, base::FEATURE_DISABLED_BY_DEFAULT);\n"
       "#endif\n")
if new in s: print("SKIP already applied: " + p); sys.exit(0)
if s.count(old) != 1: die(f"{p}: kNetworkServiceSandbox declaration changed (drift?)")
if '#include "build/build_config.h"' not in s: die(f"{p}: build/build_config.h not included (BUILDFLAG needed)")
open(p, "w").write(s.replace(old, new)); print("OK   " + p + " : network service sandbox on (Linux)")
for f, needle in [("services/network/network_sandbox_hook_linux.cc", "kNetworkServiceFileAllowlist"),
                  ("sandbox/policy/linux/bpf_network_policy_linux.cc", "NetworkProcessPolicy")]:
    if needle not in open(f).read(): die(f"{f}: expected '{needle}' — Linux network sandbox implementation changed")
print("OK   guard: Linux network sandbox policy + file allowlist present")
PY
echo "=== network service sandbox complete ==="
