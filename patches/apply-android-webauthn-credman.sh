#!/usr/bin/env bash
# Iris — Android WebAuthn (passkeys + security keys) WITHOUT Google Play services (jegly 2026-10-01; Play services is
# a strict no in the Android app, apply-android-no-gms.sh). Same approach as GrapheneOS Vanadium patches 0217, 0240 and
# 0251 (read 2026-10-01); our own code, verified against this checkout.
# Android Chromium has no USB/NFC FIDO stack of its own (device/fido hid is not built for Android). Upstream sends
# requests to Play services' FIDO2 API, or in parallel to Android 14+'s system Credential Manager, and HARD-requires
# Play services before either:
#   - AuthenticatorImpl: makeCredential/getCredential fail unless GmsCoreUtils.isWebauthnSupported(); conditional
#     mediation and isUserVerifyingPlatformAuthenticatorAvailable() are "unsupported" without it.
#   - CredManSupportProvider: Credential Manager is DISABLED when the Play services version can't be read
#     (hasOldGmsVersion: -1 -> "insufficient").
#   - Fido2CredentialRequest: residentKey=discouraged registrations (classic security keys, e.g. Gmail 2-Step) always
#     go to Play services.
# Iris, on Android 15+ (as Vanadium): skip those Play services checks, recommend the platform Credential Manager UI
# (CredManSupport.FULL_UNLESS_INAPPLICABLE = Barrier ONLY_CRED_MAN), and send every registration to Credential Manager.
# Result: passkeys come from provider apps (Bitwarden, Proton Pass, ...); a YubiKey works through a provider app that
# talks to the key (Passchain, FIDO Bridge). Iris never calls Play services. Payment credentials (SPC) stay
# unsupported (they need Play services).
# Phone-as-a-security-key for a desktop (caBLE: Bluetooth + Play services) is turned off: canDeviceSupportCable().
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
def add_const(p, line, label):
    s = open(p).read()
    if line in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    i = s.rstrip().rfind("}")
    if i < 0 or not s.rstrip().endswith("}"): die("%s: class end not found (drift?)" % p)
    open(p, "w").write(s[:i] + "\n" + line + s[i:]); print("OK   %s : %s" % (p, label))

D = "components/webauthn/android/java/src/org/chromium/components/webauthn/"
NOGMS = ("android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.VANILLA_ICE_CREAM")
CONST = ("    // Iris: on Android 15+ WebAuthn goes only through the system Credential Manager (no Play services).\n"
         "    private static boolean irisCredManOnly() {\n"
         "        return " + NOGMS + ";\n"
         "    }\n")

# 1) AuthenticatorImpl: no hard Play services requirement
p = D + "AuthenticatorImpl.java"
edit(p, "        if (!GmsCoreUtils.isWebauthnSupported()\n"
        "                || (!isChrome(mWebContents) && !GmsCoreUtils.isResultReceiverSupported())) {\n",
     "        if (!irisCredManOnly() // Iris: Credential Manager needs no Play services\n"
     "                && (!GmsCoreUtils.isWebauthnSupported()\n"
     "                        || (!isChrome(mWebContents) && !GmsCoreUtils.isResultReceiverSupported()))) {\n",
     "                        || (!isChrome(mWebContents) && !GmsCoreUtils.isResultReceiverSupported()))) {\n",
     "makeCredential: no Play services requirement")
edit(p, "        if (!GmsCoreUtils.isWebauthnSupported()\n"
        "                || (!isChrome(mWebContents) && !GmsCoreUtils.isResultReceiverSupported())\n"
        "                || (options.publicKey == null && !isPasswordOnlyFlux)) {\n",
     "        if ((!irisCredManOnly() // Iris: Credential Manager needs no Play services\n"
     "                        && (!GmsCoreUtils.isWebauthnSupported()\n"
     "                                || (!isChrome(mWebContents)\n"
     "                                        && !GmsCoreUtils.isResultReceiverSupported())))\n"
     "                || (options.publicKey == null && !isPasswordOnlyFlux)) {\n",
     "                                        && !GmsCoreUtils.isResultReceiverSupported())))\n",
     "getCredential: no Play services requirement")
edit(p, "    private boolean couldSupportConditionalMediation() {\n"
        "        return GmsCoreUtils.isWebauthnSupported() && isChrome(mWebContents);\n",
     "    private boolean couldSupportConditionalMediation() {\n"
     "        if (irisCredManOnly()) return true; // Iris\n"
     "        return GmsCoreUtils.isWebauthnSupported() && isChrome(mWebContents);\n",
     "        if (irisCredManOnly()) return true; // Iris\n        return GmsCoreUtils.isWebauthnSupported() && isChrome(",
     "conditional mediation without Play services")
edit(p, "    private boolean couldSupportUvpaa() {\n"
        "        return GmsCoreUtils.isWebauthnSupported()\n",
     "    private boolean couldSupportUvpaa() {\n"
     "        if (irisCredManOnly()) return true; // Iris\n"
     "        return GmsCoreUtils.isWebauthnSupported()\n",
     "    private boolean couldSupportUvpaa() {\n        if (irisCredManOnly()) return true; // Iris\n",
     "UVPAA without Play services")
add_const(p, CONST, "irisCredManOnly()")

# 2) CredManSupportProvider: no Play services version check; recommend the platform Credential Manager UI
p = D + "cred_man/CredManSupportProvider.java"
edit(p, "        if (notSkippedBecauseInTests() && hasOldGmsVersion()) {\n",
     "        if (!irisCredManOnly() // Iris: no Play services version check\n"
     "                && notSkippedBecauseInTests()\n"
     "                && hasOldGmsVersion()) {\n",
     "        if (!irisCredManOnly() // Iris: no Play services version check\n",
     "skip Play services version check")
edit(p, "        boolean customUiRecommended = recommender != null && recommender.recommendsCustomUi();\n",
     "        boolean customUiRecommended =\n"
     "                irisCredManOnly() // Iris: platform Credential Manager UI\n"
     "                        || (recommender != null && recommender.recommendsCustomUi());\n",
     "                irisCredManOnly() // Iris: platform Credential Manager UI\n",
     "recommend Credential Manager UI")
add_const(p, CONST, "irisCredManOnly()")

# 3) Fido2CredentialRequest: security-key registrations (residentKey=discouraged) to Credential Manager too
p = D + "Fido2CredentialRequest.java"
edit(p, "        if (!rkDiscouraged\n"
        "                && !options.isPaymentCredentialCreation\n",
     "        if ((irisCredManOnly() || !rkDiscouraged) // Iris: security keys via Credential Manager\n"
     "                && !options.isPaymentCredentialCreation\n",
     "        if ((irisCredManOnly() || !rkDiscouraged)", "registrations via Credential Manager")
add_const(p, CONST, "irisCredManOnly()")

# 4) No phone-as-a-security-key (caBLE)
p = "chrome/browser/webauthn/android/java/src/org/chromium/chrome/browser/webauthn/CableAuthenticatorModuleProvider.java"
M = "        if (IRIS_NO_CABLE) return false; // Iris: no phone-as-a-security-key (Bluetooth + Play services)\n"
edit(p, "    public static boolean canDeviceSupportCable() {\n",
     "    public static boolean canDeviceSupportCable() {\n" + M, M, "caBLE off")
add_const(p, "    private static final boolean IRIS_NO_CABLE = true; // Iris\n", "IRIS_NO_CABLE constant")
PY
