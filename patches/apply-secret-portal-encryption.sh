#!/usr/bin/env bash
# Iris — encrypt cookies/saved logins with a key from the desktop Secret portal (Linux; verified 2026-09-26).
# WHY: Chromium's os_crypt key on Linux comes from a key provider. The keyring provider (FreedesktopSecretKeyProvider)
#   needs direct D-Bus access to the keyring; inside a snap that requires the password-manager-service plug, which is
#   not auto-connected -> Chromium falls back to "basic" (fixed, public key) = cookies effectively unencrypted at rest
#   (memory/04_SNAP.md finding 9). The org.freedesktop.portal.Secret provider works through xdg-desktop-portal, which
#   a strictly confined snap reaches via its normal desktop plugs, and on a regular desktop too (GNOME implements it
#   with gnome-keyring).
# MECHANISM: chrome/browser/browser_process_impl.cc registers SecretPortalKeyProvider at precedence 15 (above the
#   keyring provider's 10) when kDbusSecretPortal (ENABLED upstream) is on, but only lets it ENCRYPT new data when
#   kSecretPortalKeyProviderUseForEncryption is on (DISABLED upstream; chrome/browser/browser_features.cc). Flip it.
# NOTE (upstream comment): once data is encrypted with the portal key this cannot be turned back off without losing
#   that data. Fine for Iris (new profiles; ~/.config/iris). If the portal is unavailable, the provider reports it and
#   the lower-precedence providers are used.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "chrome/browser/browser_features.cc"
s = open(p).read()
on  = re.compile(r"BASE_FEATURE\(kSecretPortalKeyProviderUseForEncryption,\s*base::FEATURE_ENABLED_BY_DEFAULT\)")
off = re.compile(r"(BASE_FEATURE\(kSecretPortalKeyProviderUseForEncryption,\s*)base::FEATURE_DISABLED_BY_DEFAULT\)")
if on.search(s): print("SKIP already applied: " + p)
elif len(off.findall(s)) == 1:
    open(p, "w").write(off.sub(r"\1base::FEATURE_ENABLED_BY_DEFAULT)", s, count=1)); print("OK   " + p + " : portal key used for encryption")
else: die(f"{p}: kSecretPortalKeyProviderUseForEncryption declaration not found exactly once (drift?)")
if not re.search(r"BASE_FEATURE\(kDbusSecretPortal,\s*base::FEATURE_ENABLED_BY_DEFAULT\)", open(p).read()):
    die("kDbusSecretPortal is no longer enabled by default -> the portal provider would not be registered")
b = open("chrome/browser/browser_process_impl.cc").read()
if "SecretPortalKeyProvider" not in b or "kSecretPortalKeyProviderUseForEncryption" not in b:
    die("browser_process_impl.cc no longer wires SecretPortalKeyProvider with the encryption flag")
print("OK   guard: portal provider registered (kDbusSecretPortal on) and wired to the flag")
PY
echo "=== Secret portal encryption complete ==="
