#!/usr/bin/env bash
# Iris — more Site-settings defaults = "Not allowed" (jegly 2026-10-09, from the Android Site settings screens: "these
# should be the defaults ... same should follow for the equivalent on desktop"; verified against 156.0.8078.11).
# components/content_settings/core/browser/content_settings_registry.cc, ONE shared list for desktop and Android. Every
# type below changes its DEFAULT to CONTENT_SETTING_BLOCK (checked: BLOCK is in each type's valid_settings, no #if
# between the name and its default). Users who already chose a value keep it; new profiles start blocked, and a site
# can still be allowed per site (or the default changed) in Site settings.
#   ask -> block:  storage access (+ top-level), local network access / local network / loopback network, automatic
#                  downloads, NFC, USB, Serial, Bluetooth (+ scanning), HID, smart card, file system read/write,
#                  VR, AR, hand tracking, window management, keyboard lock, auto picture-in-picture, web app
#                  installation, camera pan/tilt/zoom, speaker selection, local fonts, web printing, captured
#                  surface control.
#   allow -> block: payment handler, federated identity API (+ automatic re-authentication), direct sockets
#                  (features Iris already removes: the Settings screens now say so).
# Left as they are on purpose: cookies (third-party already blocked), images, JavaScript, sound, autoplay (own switch),
# persistent storage and pointer lock (ask), protected content (ask, apply-site-settings-defaults.sh).
# STATUS 2026-10-09: copy-tested only, NOT compile-proven (content_settings_registry.o; the registry has DCHECKs).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "components/content_settings/core/browser/content_settings_registry.cc"
s = open(p).read()
TYPES = ("STORAGE_ACCESS TOP_LEVEL_STORAGE_ACCESS LOCAL_NETWORK_ACCESS LOCAL_NETWORK LOOPBACK_NETWORK AUTOMATIC_DOWNLOADS "
         "NFC USB_GUARD SERIAL_GUARD BLUETOOTH_GUARD HID_GUARD BLUETOOTH_SCANNING SMART_CARD_GUARD "
         "FILE_SYSTEM_WRITE_GUARD FILE_SYSTEM_READ_GUARD VR AR HAND_TRACKING WINDOW_MANAGEMENT KEYBOARD_LOCK "
         "AUTO_PICTURE_IN_PICTURE WEB_APP_INSTALLATION CAMERA_PAN_TILT_ZOOM SPEAKER_SELECTION LOCAL_FONTS WEB_PRINTING "
         "CAPTURED_SURFACE_CONTROL PAYMENT_HANDLER FEDERATED_IDENTITY_API FEDERATED_IDENTITY_AUTO_REAUTHN_PERMISSION "
         "DIRECT_SOCKETS").split()
done = changed = 0
for t in TYPES:
    pat = re.compile(r'(Register\(\s*ContentSettingsType::%s,\s*"[^"]+",\s*)CONTENT_SETTING_(\w+)' % t)
    ms = pat.findall(s)
    if len(ms) != 1: die("%s: %s registration not found exactly once (drift?)" % (p, t))
    i = pat.search(s).start(); j = s.find(");", i)
    blk = s[i:j]
    if "CONTENT_SETTING_BLOCK" not in blk.split("valid_settings", 1)[-1] and "BLOCK" not in blk.split(",", 3)[-1]:
        die("%s: BLOCK is not a valid setting for %s" % (p, t))
    if ms[0][1] == "BLOCK": done += 1; continue
    if ms[0][1] not in ("ASK", "ALLOW"): die("%s: unexpected default %s for %s" % (p, ms[0][1], t))
    s = pat.sub(lambda m: m.group(1) + "CONTENT_SETTING_BLOCK", s, count=1)
    changed += 1
if changed:
    open(p, "w").write(s); print("OK   %s : %d defaults -> BLOCK (%d already)" % (p, changed, done))
else:
    print("SKIP already applied: %s (%d already BLOCK)" % (p, done))
PY
echo "=== site settings defaults (round 2) complete ==="
