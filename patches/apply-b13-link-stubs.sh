#!/usr/bin/env bash
# Iris — B13 link fix (2026-09-28). With use_bluez=false and enable_media_remoting=false the sources that define
# these symbols are not built, but four callers use them unconditionally -> undefined symbols at `chrome` link:
#  - chrome_browser_main_linux.cc: bluez::BluezDBusManager::Initialize/Shutdown (upstream assumes BlueZ whenever
#    USE_DBUS on Linux). Removed: with use_bluez=false device/bluetooth uses its stub adapter, nothing needs BlueZ.
#  - metrics/bluetooth_metrics_provider.cc: floss::features::IsFlossEnabled() (floss_features.cc is bluez-only).
#    Reports BlueZ; metrics are not uploaded in Iris anyway.
#  - media/router/mojo/media_router_desktop.cc and media/cast_mirroring_service_host.cc: CastRemotingConnector
#    (cast_remoting_connector.cc is enable_media_remoting-only). Guarded by BUILDFLAG(ENABLE_MEDIA_REMOTING);
#    media router is off at runtime (apply-media-router-off.sh), so the code is dead in Iris.
# Chosen over flipping the args back: those flip widely included buildflag headers (long rebuild). Only four
# files recompile. Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, pairs, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    for old, new in pairs:
        if s.count(old) != 1: die("%s: anchor not found exactly once for %s (drift?):\n%s" % (p, label, old))
        s = s.replace(old, new, 1)
    open(p, "w").write(s); print("OK   %s : %s" % (p, label))

M = "Iris (apply-b13-link-stubs.sh)"

edit("chrome/browser/chrome_browser_main_linux.cc", [
    ('#if BUILDFLAG(USE_DBUS)\n'
     '  bluez::BluezDBusManager::Initialize(\n'
     '      dbus_thread_linux::GetSharedSystemBus().get());\n'
     '  session_end_listener_ = SessionEndListenerLinux::Create();\n',
     '#if BUILDFLAG(USE_DBUS)\n'
     '  // ' + M + ': built with use_bluez=false, no BlueZ D-Bus manager.\n'
     '  session_end_listener_ = SessionEndListenerLinux::Create();\n'),
    ('  session_end_listener_.reset();\n'
     '#endif\n'
     '  bluez::BluezDBusManager::Shutdown();\n',
     '  session_end_listener_.reset();\n'
     '#endif\n'
     '  // ' + M + ': no BluezDBusManager::Shutdown (use_bluez=false).\n'),
    ('#include "device/bluetooth/dbus/bluez_dbus_manager.h"\n', ''),
], M, "no BlueZ D-Bus manager")

edit("chrome/browser/metrics/bluetooth_metrics_provider.cc", [
    ('#include "device/bluetooth/floss/floss_features.h"\n', ''),
    ('                                floss::features::IsFlossEnabled()\n'
     '                                    ? BluetoothStackName::kFloss\n'
     '                                    : BluetoothStackName::kBlueZ);\n',
     '                                // ' + M + ': no Floss (use_bluez=false)\n'
     '                                BluetoothStackName::kBlueZ);\n'),
], M, "no Floss check")

edit("chrome/browser/media/router/mojo/media_router_desktop.cc", [
    ('#include "chrome/browser/media/cast_remoting_connector.h"\n',
     '#include "chrome/browser/media/cast_remoting_connector.h"\n'
     '#include "media/media_buildflags.h"\n'),
    ('    // Ensure the CastRemotingConnector is created before mirroring starts.\n'
     '    CastRemotingConnector* const connector =\n'
     '        CastRemotingConnector::Get(web_contents);\n'
     '    connector->ResetRemotingPermission();\n',
     '#if BUILDFLAG(ENABLE_MEDIA_REMOTING)  // ' + M + '\n'
     '    // Ensure the CastRemotingConnector is created before mirroring starts.\n'
     '    CastRemotingConnector* const connector =\n'
     '        CastRemotingConnector::Get(web_contents);\n'
     '    connector->ResetRemotingPermission();\n'
     '#endif\n'),
], M, "remoting connector guarded")

edit("chrome/browser/media/cast_mirroring_service_host.cc", [
    ('#include "chrome/browser/media/cast_remoting_connector.h"\n',
     '#include "chrome/browser/media/cast_remoting_connector.h"\n'
     '#include "media/media_buildflags.h"\n'),
    ('    if (source_contents) {\n'
     '      CastRemotingConnector::Get(source_contents)\n'
     '          ->ConnectWithMediaRemoter(std::move(remoter), std::move(receiver));\n'
     '    }\n',
     '#if BUILDFLAG(ENABLE_MEDIA_REMOTING)  // ' + M + '\n'
     '    if (source_contents) {\n'
     '      CastRemotingConnector::Get(source_contents)\n'
     '          ->ConnectWithMediaRemoter(std::move(remoter), std::move(receiver));\n'
     '    }\n'
     '#else\n'
     '    (void)source_contents;\n'
     '#endif\n'),
], M, "remoting connector guarded")
PY
echo "=== B13 link stubs complete ==="
