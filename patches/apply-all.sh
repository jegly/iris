#!/usr/bin/env bash
# Iris — apply EVERY active patch, in order. Idempotent: re-running on an already-patched tree
# prints SKIP for each. Stops on the first ERROR (= rebase drift; fix that script before building).
# Usage: ~/Documents/iris/patches/apply-all.sh [chromium-src-dir]   (default ~/Documents/chromium/src)
# NOT included: patches/shelved/* (deliberately not applied — see their headers).
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
# Never edit the tree while a build is compiling it (inconsistent objects). Override: IRIS_FORCE=1
# Match the real builder PROCESS NAMES (siso / ninja), not command-line text (text matching false-positives on
# any shell whose command merely mentions autoninja).
if [ "${IRIS_FORCE:-0}" != "1" ] && { pgrep -x siso >/dev/null 2>&1 || pgrep -x ninja >/dev/null 2>&1; }; then
  echo "REFUSING: a Chromium build is running (autoninja/siso). Re-run after it finishes." >&2; exit 2
fi
PATCHES=(
  apply-feature-defaults        # StrictOriginIsolation, OriginKeyedProcesses, PA advanced checks
  apply-degoogle-prefs          # <a ping>, nav-error phone-home, sign-in off, AcceptCH off, ReduceAcceptLanguage
  apply-blink-features          # DocumentPatching off
  apply-rebrand                 # Iris / jegly strings + icons (needs branding/icon/generated/)
  apply-degoogle-group3         # search-suggest, media-router, payments, sensors, bg-sync, 3p cookies
  apply-tls-hardening           # min TLS 1.3 + ECH guard
  apply-remove-ai-page          # settings AI page gone
  apply-default-search          # DuckDuckGo default (IRIS_SEARCH_ENGINE to swap)
  apply-search-list-ddg         # DDG selectable in every region
  apply-popup-hardening         # block popups without a trusted user gesture
  apply-download-quarantine     # downloads never auto-open
  apply-jitless-runtime         # JIT off for web content -> WebAssembly global absent
  apply-content-settings-group4 # Idle Detection + Web MIDI BLOCK
  # --- added 2026-09-26 (after the official build that started 10:27 that day) ---
  apply-webgpu-off              # kWebGPUService default OFF (was silently ON: Linux here + Android)
  apply-default-switches        # launcher switches compiled in (Android has no launcher)
  apply-flags-group5            # jegly's flags: Rusty ICO/JPEG, Android site-per-process, 3 Google svcs off
  apply-webrtc-off              # RTCPeerConnection gated behind IrisWebRTC (off)
  apply-rebrand-android         # Android app name/icons (needs branding/icon/generated-android/)
  apply-doh-secure              # DoH secure mode, Quad9 default, 15-resolver picker (Google hidden)
  apply-privacy-batch1          # window.name, FedCM, compression dicts, preloading, text fragments, SXG, translate, autofill server, feed
  apply-fingerprint-apis        # speechSynthesis, fetchLater, getBattery, getGamepads, sendBeacon, userAgentData off
  apply-compiler-hardening      # strong protector, stack-clash, Android SCS+strong (FULL REBUILD)
  apply-vanadium-parity         # local NTP, no logo/popular-sites/Google favicons, contextual search off, SB surveys/deep-scan off, DRM preprovisioning off, Android FRE skip, full hostnames/URLs
  apply-fieldtrial-wins         # subframe error-page isolation, gesture-gated prompts, provisioning hardening, auto-revoke unused permissions
  # --- Phase A (approved 2026-09-26; research/phase-a-decisions.md). apply-default-switches above also carries
  #     the Phase-A Blink cut list (41 features) and upgrades an already-inserted list in place. ---
  apply-phase-a-flips           # HSTS top-level only, HTTPS-Only, PDF external, spellcheck/autofill/pw-save off, 5 permissions BLOCK, Android location w/o Play Services
  apply-phase-a-gates           # new Iris* gates: screen details, keyboard map, badging, vibration, WCO, ink, breakout box, netinfo (json5)
  apply-ua-client-hints-off     # never any Sec-CH-UA*: not by default, and sites cannot opt in (Accept-CH/Critical-CH/meta)
  apply-origin-trials-off       # no origin trials: tokens cannot re-enable cut features
  apply-android-user-ca-distrust # Android: user-installed CAs not trusted (feature IrisTrustAndroidUserCAs)
  apply-android-scs-target-only # Android: shadow call stack only for the arm64 target toolchain (gn assert on host)
  apply-android-omnibox-novr    # Android: omnibox/searchbox build with enable_vr=false (guards GetVectorIcon callers)
  apply-orb-logo                # product vector icons -> orb
  apply-hw-values-fixed         # navigator.hardwareConcurrency=8, deviceMemory=8 on every device
  apply-media-router-off        # Cast/Media Router off for real (kMediaRouter; the pref default was a no-op)
  apply-print-discovery-off     # printing off (pref); guard: Media Router off => no mDNS discovery
  apply-gpc-on                  # Global Privacy Control on (compiled-in --enable-features, merged)
  apply-docwrite-block          # document.write cross-site script block, compiled in (needs default-switches + gpc-on)
  apply-secret-portal-encryption # Linux: encrypt cookies/logins with the Secret-portal key (fixes snap "basic" store)
  apply-tracking-param-strip    # strip utm_*/fbclid/gclid/... from navigations (new code in patches/src/)
  apply-network-sandbox         # Linux: network service sandboxed (seccomp + file allowlist) — RUNTIME TEST
  apply-payment-request-off     # Payment Request API + its Mojo binding gone (kWebPayments off)
  apply-no-platform-policy      # no admin/MDM policies (Linux /etc/chromium/policies, Android app restrictions)
  apply-wakelock-gate           # navigator.wakeLock actually removed (IDL had no gate)
  apply-managed-config-gate     # navigator.managed actually removed (IDL had no gate)
  apply-rebrand-logos           # remaining Chromium logos: WebUI 16/32 px, wordmarks, product SVGs, sidebar icon
  apply-rebrand-strings         # visible 'Chrome' wording -> Iris (theme 'Iris Colors', 'Built-in panels', menus, dialogs)
  apply-accept-language-one     # Accept-Language = the first language only (the reduce feature did not do it)
  apply-extension-update-toggle # B12: Settings -> System toggle, extension updates default OFF
  apply-settings-you-and-iris   # "You and Google" -> "You and Iris", Google services hidden, autocomplete toggle -> Privacy
  apply-catppuccin-default      # B9 part 1: dark mode default + Catppuccin Mocha sys colours (desktop)
  apply-gcm-off                 # GCM/FCM never starts: no Google device check-in / registration at startup
  apply-app-menu-trim           # ⋮ menu: no Print (printing off), no Translate
  apply-omnibox-orb-raster      # address-bar chip on chrome:// pages = the real orb image (gradient)
  apply-bad-flags-iris          # no 'unsupported flag' bar for Iris's own --disable-blink-features
  apply-no-api-keys-bar         # no 'Google API keys are missing' bar (no keys on purpose)
  apply-no-desktop-accent       # Linux: ignore GNOME accent colour (brown new-tab flash)
  apply-download-review-stub    # B13 build fix: download bubble stub for ShouldPromptReviewForDownload (content analysis off)
  apply-b13-link-stubs          # B13 link fix: no BlueZ/Floss calls (use_bluez=false), remoting guarded (media_remoting=false)
  apply-iris-permissions        # Phase B batch: IRIS_WEBGL (B1), IRIS_GOOGLE_SIGNIN (B5), IRIS_USER_AGENT (B2) + strings — LONG REBUILD
  apply-extension-update-strings # B12: translatable toggle label (needs apply-iris-permissions)
  apply-forget-site             # B6: Page Info 'Forget this site when I close Iris' (needs apply-iris-permissions)
  apply-shredder                # B7: automatic data deletion toggle, off by default (needs apply-iris-permissions)
  apply-clipboard-clear         # B7: copied text cleared from the clipboard after 30 s while deletion is on
  apply-user-agent              # B2: per-site browser identity (needs apply-iris-permissions)
  apply-fingerprint             # B4: canvas + audio fingerprint protection per site (needs apply-iris-permissions)
  apply-page-info-icons         # Page Info icons for the Iris rows (else NOTREACHED crash on opening Page Info)
  apply-page-info-tls           # Page Info: TLS protocol/cipher/key exchange/signature/ECH under the certificate row
  apply-page-info-identity      # Page Info: quick per-site browser identity menu (needs apply-user-agent + apply-forget-site)
  apply-ua-navigator-consistency # navigator.platform/vendor/productSub follow the per-site identity
  apply-hide-avatar-button      # no toolbar profile button for a single normal profile (kept in Incognito/Guest)
  apply-downloads-icon-autohide # unpinned downloads button hides 10 s after a download finishes (upstream 60 min)
  apply-palettes-picker         # B9 part 2: Iris palettes (ui/color/iris_palettes.h) in the Customize colour picker
  apply-glass                   # B9: opt-in glass look for the built-in pages (after apply-shredder)
  apply-app-lock                # B8 app lock at start + B10 passphrase encryption (os_crypt_async provider)
  apply-keyring-skip            # no keyring prompt while the Iris passphrase lock is on (needs apply-app-lock)
  apply-storage-encryption      # bookmarks + open-tab session files encrypted ONLY (upstream wrote a plain-text copy too)
  apply-extra-hardening         # passwords fill only on account select; scheme- + port-bound cookies
  apply-webui-font              # built-in pages: IBM Plex Sans text, DotGothic16 headers (bundled fonts)
  apply-deb-rebrand             # .deb identity iris-browser (jjjegly@gmail.com, github.com/jegly/iris) + desktop/icon/profile dir names
  apply-adblock                 # LAST: needs adblock/dist/ruleset.pb (adblock/build-ruleset.sh); EasyList+EasyPrivacy on all sites
  apply-third-party-notices     # fonts (OFL) + Catppuccin (MIT) notices in /usr/share/doc (after apply-adblock)
)
for p in "${PATCHES[@]}"; do
  echo "================ $p"
  "$DIR/$p.sh" "$SRC"
done
echo "=== ALL ${#PATCHES[@]} Iris patches applied (or already present) ==="
