#!/usr/bin/env bash
# Iris — report common FIXED hardware values to websites (jegly 2026-09-26, final release; verified 2026-09-26).
# Fingerprinting: navigator.hardwareConcurrency (exact CPU thread count) and navigator.deviceMemory (RAM bucket,
# 2..32 GB desktop / 1..8 GB Android) both add entropy. Iris reports 8 and 8 on every device, both platforms —
# the most common real values, so Iris users blend together instead of each exposing their hardware.
# MECHANISM (single sources):
# - hardwareConcurrency: blink::NavigatorConcurrentHardware::hardwareConcurrency()
#   (third_party/blink/renderer/core/frame/navigator_concurrent_hardware.cc) — used by Navigator AND WorkerNavigator
#   through NavigatorBase::hardwareConcurrency() (DevTools' override probe still applies on top).
# - deviceMemory: blink::ApproximatedDeviceMemory (third_party/blink/common/device_memory/approximated_device_memory.cc)
#   feeds navigator.deviceMemory and the Device-Memory client hint (frame_fetch_context.cc, content client_hints.cc);
#   no internal memory heuristics read it. The value is pinned after upstream's calculation + clamps.
# Cost: sites that size worker pools from hardwareConcurrency assume 8 threads; harmless on smaller CPUs.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(path, old, new, marker):
    s = open(path).read()
    if marker in s: print("SKIP already applied: " + path); return
    if s.count(old) != 1: die(f"{path}: expected 1 match, found {s.count(old)} (drift?): {old[:70]!r}")
    open(path, "w").write(s.replace(old, new, 1)); print("OK   " + path)

edit("third_party/blink/renderer/core/frame/navigator_concurrent_hardware.cc",
     "unsigned NavigatorConcurrentHardware::hardwareConcurrency() const {\n"
     "  return static_cast<unsigned>(base::SysInfo::NumberOfProcessors());\n}",
     "unsigned NavigatorConcurrentHardware::hardwareConcurrency() const {\n"
     "  // Iris: a common fixed value on every device (anti-fingerprinting).\n"
     "  return 8u;\n}",
     "// Iris: a common fixed value on every device")
# base/system/sys_info.h is now unused in that file -> drop the include (no unused-include warning in clang, but keep it tidy
# only if nothing else uses base::SysInfo there).
p = "third_party/blink/renderer/core/frame/navigator_concurrent_hardware.cc"
s = open(p).read()
if "base::SysInfo" not in s and '#include "base/system/sys_info.h"\n' in s:
    open(p, "w").write(s.replace('#include "base/system/sys_info.h"\n\n', "", 1).replace('#include "base/system/sys_info.h"\n', "", 1))
    print("OK   " + p + " (unused sys_info include removed)")

edit("third_party/blink/common/device_memory/approximated_device_memory.cc",
     "  if (approximated_device_memory_gb_ < kMinMemory) {\n"
     "    approximated_device_memory_gb_ = kMinMemory;\n"
     "  } else if (approximated_device_memory_gb_ > kMaxMemory) {\n"
     "    approximated_device_memory_gb_ = kMaxMemory;\n"
     "  }\n",
     "  if (approximated_device_memory_gb_ < kMinMemory) {\n"
     "    approximated_device_memory_gb_ = kMinMemory;\n"
     "  } else if (approximated_device_memory_gb_ > kMaxMemory) {\n"
     "    approximated_device_memory_gb_ = kMaxMemory;\n"
     "  }\n"
     "  // Iris: report a common fixed value on every device (anti-fingerprinting).\n"
     "  approximated_device_memory_gb_ = 8.0f;\n",
     "// Iris: report a common fixed value on every device")
PY
echo "=== fixed hardware values complete ==="
