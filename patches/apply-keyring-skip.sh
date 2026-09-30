#!/usr/bin/env bash
# Iris — no GNOME keyring / Secret portal prompt while the Iris passphrase lock is on (jegly 2026-09-30).
# With the lock on, IrisKeyProvider (precedence 20, AES-256-GCM, passphrase-protected key) encrypts all new
# cookies/logins/bookmarks/sessions, so asking the keyring (FreedesktopSecretKeyProvider, 10) or the Secret portal
# (SecretPortalKeyProvider, 15) only produces the "unlock your keyring" prompt. Skip registering both then.
# PosixKeyProvider (5) stays, so data written earlier with its fixed key remains readable.
# COST: data written earlier with a REAL keyring key (someone who used a keyring before turning the lock on)
# becomes unreadable (e.g. logged out of sites once). Lock off = upstream behaviour, unchanged.
# Guarded; idempotent; fails loudly on drift. Needs apply-app-lock first.
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
p = "chrome/browser/browser_process_impl.cc"
if "IrisKeyProvider::kPrecedence" not in open(p).read(): die("run apply-app-lock.sh first")
edit(p, '#include "chrome/browser/iris/iris_key_provider.h"  // Iris (B10)\n',
     '#include "chrome/browser/iris/iris_app_lock.h"  // Iris (keyring skip)\n'
     '#include "chrome/browser/iris/iris_key_provider.h"  // Iris (B10)\n',
     "chrome/browser/iris/iris_app_lock.h", "include")
edit(p,
     '  if (password_store != "basic") {\n'
     '    if (base::FeatureList::IsEnabled(features::kDbusSecretPortal)) {\n',
     '  // Iris: with the passphrase lock on, Iris\'s own key encrypts (IrisKeyProvider)\n'
     '  // and the keyring / Secret portal are never asked -> no keyring prompt.\n'
     '  const bool iris_lock_on = iris_app_lock::IsEnabled(local_state());\n'
     '  if (password_store != "basic" && !iris_lock_on) {\n'
     '    if (base::FeatureList::IsEnabled(features::kDbusSecretPortal)) {\n',
     "iris_lock_on = iris_app_lock::IsEnabled", "portal skipped when locked")
edit(p,
     '  providers.emplace_back(\n'
     '      /*precedence=*/10u,\n'
     '      std::make_unique<os_crypt_async::FreedesktopSecretKeyProvider>(\n'
     '          password_store, l10n_util::GetStringUTF8(IDS_PRODUCT_NAME), nullptr));\n',
     '  if (!iris_lock_on) {\n'
     '    providers.emplace_back(\n'
     '        /*precedence=*/10u,\n'
     '        std::make_unique<os_crypt_async::FreedesktopSecretKeyProvider>(\n'
     '            password_store, l10n_util::GetStringUTF8(IDS_PRODUCT_NAME),\n'
     '            nullptr));\n'
     '  }\n',
     "  if (!iris_lock_on) {\n", "keyring skipped when locked")
PY
echo "=== keyring skip complete ==="
