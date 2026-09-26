#!/usr/bin/env bash
# Iris — compiler hardening (verified against checkout 2026-09-26). jegly approved:
#   Ubuntu : -fstack-protector-strong (was plain -fstack-protector on POSIX) + -fstack-clash-protection (Linux)
#            (+ zero-init stack vars via gn arg init_stack_vars_zero=true in build/args-linux.gn)
#   Android: zero-init + shadow call stack are gn args (build/args-android.gn); here: keep the strong
#            stack protector ALONGSIDE SCS (Vanadium 0016) + stack-clash on arm64 (Vanadium 0010).
# Already present upstream (no change): CFI vcall/icall, ThinLTO, _FORTIFY_SOURCE=3, libc++ extensive hardening,
# array-bounds/return/unreachable trap sanitizers, -fno-strict-overflow (wrap), full RELRO/NX/PIE,
# ARM PAC+BTI on arm64 (arm_control_flow_integrity="standard").
# !!! Changes GLOBAL cflags -> the next build recompiles EVERYTHING (full rebuild). Batch with other changes.
# !!! Edits build/config/compiler/BUILD.gn -> NEVER apply while a build is running (apply-all.sh refuses).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
p = "build/config/compiler/BUILD.gn"
s = o = open(p).read()
def die(m): sys.stderr.write("ERROR: "+m+"\n"); sys.exit(1)

# 1) POSIX stack protector -> strong
old1 = '''        if (current_os != "aix") {
          # Not available on aix.
          cflags += [ "-fstack-protector" ]
        }'''
new1 = '''        if (current_os != "aix") {
          # Not available on aix.
          # Iris: strong variant (protects any function with local arrays or address-taken locals).
          cflags += [ "-fstack-protector-strong" ]
        }'''
if "# Iris: strong variant" in s: print("SKIP stack-protector-strong already applied")
elif s.count(old1) == 1: s = s.replace(old1, new1); print("OK   posix -fstack-protector -> -fstack-protector-strong")
else: die(f"posix stack-protector block found {s.count(old1)}x (drift?)")

# 2) stack clash protection on Linux, right after the -fno-strict-overflow block
old2 = '''    } else {
      cflags += [ "-fno-strict-overflow" ]
    }
  }
'''
new2 = old2 + '''
  # Iris: stack clash protection (Linux + Android arm64 as Vanadium 0010) — probe large stack allocations.
  if (is_clang && (is_linux || (is_android && current_cpu == "arm64"))) {
    cflags += [ "-fstack-clash-protection" ]
  }
'''
if "# Iris: stack clash protection" in s: print("SKIP stack-clash already applied")
elif s.count(old2) == 1: s = s.replace(old2, new2); print("OK   -fstack-clash-protection added (Linux + Android arm64)")
else: die(f"-fno-strict-overflow anchor found {s.count(old2)}x (drift?)")


# 3) Android: keep -fstack-protector-strong alongside the shadow call stack (Vanadium 0016).
#    Upstream puts "-fno-stack-protector" in scs_parameters (cflags AND ldflags). We drop it and add the strong
#    protector to cflags ONLY — in ldflags a compile-only flag could trip -Werror unused-argument at link.
old3 = '''      scs_parameters = [
        "-fsanitize=shadow-call-stack",
        "-fno-stack-protector",
      ]
      cflags += scs_parameters
      ldflags += scs_parameters'''
new3 = '''      scs_parameters = [ "-fsanitize=shadow-call-stack" ]
      cflags += scs_parameters
      ldflags += scs_parameters

      # Iris (as Vanadium 0016): strong stack protector as a fallback alongside SCS (compile-only flag).
      cflags += [ "-fstack-protector-strong" ]'''
if "# Iris (as Vanadium 0016)" in s: print("SKIP SCS+strong already applied")
elif s.count(old3) == 1: s = s.replace(old3, new3); print("OK   Android: -fstack-protector-strong kept alongside shadow call stack")
else: die(f"SCS block found {s.count(old3)}x (drift?)")

if s != o: open(p, "w").write(s)
PY
echo "=== compiler hardening complete ==="
