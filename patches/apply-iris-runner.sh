#!/usr/bin/env bash
# Iris — the offline game is RUNNER, jegly's 3D take on the dinosaur game (jegly 2026-10-10: "build it in to replace
# the dino game"; verified against 156.0.8078.11). Applies to the offline error page and chrome://dino (the same page:
# content/browser/webui/network_error_url_loader.cc serves chrome://dino as ERR_INTERNET_DISCONNECTED).
#  - patches/src/components/neterror/resources/iris_runner/iris_runner.html: the game, one file (three.js r169, MIT,
#    inlined; no network). Iris additions: retro touch pad (D-pad + A/B) on touch screens, high score kept in the
#    dino's saved high score. Packed as IDR_IRIS_RUNNER_HTML (components resources, brotli), NOT inlined into
#    neterror.html, so ordinary error pages stay small.
#  - neterror (offline.ts): when the player starts the game (Space / Up / tap, the same moment the dino would start)
#    and WebGL 2 works on the page, the page is replaced with the game (document.open/write); otherwise the classic
#    dino plays as before (e.g. "Turn WebGL off completely" in Iris hardening, or a blocklisted GPU).
#  - renderer: errorPageController.irisRunnerSource() returns the game from the resource bundle (error pages only;
#    the controller is installed on error pages only).
#  - browser: the error page is exempt from the per-site WebGL block (IRIS_WEBGL, apply-iris-permissions.sh); the
#    page only runs Iris's own code (jegly 2026-10-10, memory/02_DECISIONS.md). kDisable3DAPIs still wins.
#    JIT needs no change: the error page's site (chrome-error://) is not a web-safe scheme, so
#    ChromeContentBrowserClient::IsJitDisabledForSite() already keeps JIT on there.
#  - High score: stored through the existing NetworkEasterEgg pref in the dino's units (raw distance; shown x0.025),
#    so the two games show comparable numbers.
# Needs apply-iris-permissions.sh (WebGL gate anchor). Desktop + Android.
# STATUS 2026-10-10: copy-tested only, NOT compile-proven (net_error_page_controller.o, chrome_content_browser_client.o,
#   neterror bundle incl. its tsc + eslint step, components resources).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
to="components/neterror/resources/iris_runner/iris_runner.html"; from="$DIR/src/$to"
[ -s "$from" ] || { echo "ERROR: $from missing" >&2; exit 1; }
mkdir -p "$(dirname "$to")"
if cmp -s "$from" "$to"; then echo "SKIP up to date: $to"; else cp "$from" "$to"; echo "OK   $to"; fi
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

# --- resource ---
edit("components/resources/neterror_resources.grdp",
     '  <include name="IDR_NET_ERROR_HTML" file="../neterror/resources/neterror.html" flattenhtml="true" type="BINDATA"/>\n',
     '  <include name="IDR_NET_ERROR_HTML" file="../neterror/resources/neterror.html" flattenhtml="true" type="BINDATA"/>\n'
     '  <!-- Iris: the offline game (patches/apply-iris-runner.sh) -->\n'
     '  <include name="IDR_IRIS_RUNNER_HTML" file="../neterror/resources/iris_runner/iris_runner.html" type="BINDATA" compress="brotli"/>\n',
     "IDR_IRIS_RUNNER_HTML", "game resource")

# --- renderer: errorPageController.irisRunnerSource() ---
h = "chrome/renderer/net/net_error_page_controller.h"
edit(h, "  bool TrackEasterEgg();\n",
     "  bool TrackEasterEgg();\n\n"
     "  // Iris: the built-in offline game (apply-iris-runner.sh).\n"
     "  std::string IrisRunnerSource();\n",
     "std::string IrisRunnerSource();", "header: game source")
s = open(h).read()
if "#include <string>" not in s:
    edit(h, '#include "base/memory/weak_ptr.h"\n',
         '#include <string>  // Iris\n\n#include "base/memory/weak_ptr.h"\n', "#include <string>  // Iris", "header: <string>")
c = "chrome/renderer/net/net_error_page_controller.cc"
edit(c, '#include "chrome/renderer/net/net_error_page_controller.h"\n',
     '#include "chrome/renderer/net/net_error_page_controller.h"\n'
     '#include "components/grit/components_resources.h"  // Iris\n'
     '#include "ui/base/resource/resource_bundle.h"  // Iris\n',
     'components_resources.h"  // Iris', "includes")
edit(c, "bool NetErrorPageController::UpdateEasterEggHighScore(int high_score) {\n",
     "std::string NetErrorPageController::IrisRunnerSource() {\n"
     "  return ui::ResourceBundle::GetSharedInstance().LoadDataResourceString(\n"
     "      IDR_IRIS_RUNNER_HTML);\n"
     "}\n\n"
     "bool NetErrorPageController::UpdateEasterEggHighScore(int high_score) {\n",
     "NetErrorPageController::IrisRunnerSource() {", "game source")
edit(c, '      .SetMethod("trackEasterEgg", &NetErrorPageController::TrackEasterEgg)\n',
     '      .SetMethod("trackEasterEgg", &NetErrorPageController::TrackEasterEgg)\n'
     '      .SetMethod("irisRunnerSource",  // Iris\n'
     '                 &NetErrorPageController::IrisRunnerSource)\n',
     '"irisRunnerSource"', "JS binding")

# --- neterror: types + start hook ---
n = "components/neterror/resources/neterror.ts"
edit(n, "    initializeEasterEggHighScore: (score: number) => void;\n  }\n}\n",
     "    initializeEasterEggHighScore: (score: number) => void;\n"
     "    // Iris: the built-in 3D runner (apply-iris-runner.sh).\n"
     "    irisRunnerBest?: number;\n"
     "    irisRunnerSaveBest?: (score: number) => void;\n  }\n}\n",
     "irisRunnerSaveBest?:", "Window types")
edit(n, "  trackEasterEgg(): void;\n}\n",
     "  trackEasterEgg(): void;\n"
     "  irisRunnerSource?(): string;  // Iris (apply-iris-runner.sh)\n}\n",
     "irisRunnerSource?(): string;", "controller type")
o = "components/neterror/resources/dino_game/offline.ts"
edit(o, "          // Starting the game for the first time.\n          if (!this.playing) {\n",
     "          // Starting the game for the first time.\n          if (!this.playing) {\n"
     "            // Iris: the 3D runner replaces the classic game when WebGL 2\n"
     "            // works on this page (apply-iris-runner.sh).\n"
     "            if (this.irisStartRunner3d()) {\n"
     "              return;\n"
     "            }\n",
     "if (this.irisStartRunner3d()) {", "start hook")
edit(o, "  private stop() {\n",
     "  // Iris (apply-iris-runner.sh): replaces this page with RUNNER, the built-in\n"
     "  // 3D game. Returns false, keeping the classic game, without WebGL 2.\n"
     "  private irisStartRunner3d(): boolean {\n"
     "    const controller = window.errorPageController;\n"
     "    if (!controller || !controller.irisRunnerSource) {\n"
     "      return false;\n"
     "    }\n"
     "    const probe = document.createElement('canvas').getContext('webgl2');\n"
     "    if (!probe) {\n"
     "      return false;\n"
     "    }\n"
     "    const loseContext = probe.getExtension('WEBGL_lose_context');\n"
     "    if (loseContext) {\n"
     "      loseContext.loseContext();\n"
     "    }\n"
     "    const source = controller.irisRunnerSource();\n"
     "    if (!source) {\n"
     "      return false;\n"
     "    }\n"
     "    // Shares the dino's saved high score, in the dino's units\n"
     "    // (DistanceMeter shows raw distance x 0.025).\n"
     "    const coefficient = 0.025;\n"
     "    window.irisRunnerBest = Math.round(this.highestScore * coefficient);\n"
     "    window.irisRunnerSaveBest = (score: number) => {\n"
     "      controller.updateEasterEggHighScore(Math.ceil(score / coefficient));\n"
     "    };\n"
     "    controller.trackEasterEgg();\n"
     "    this.stop();\n"
     "    document.open();\n"
     "    document.write(source);\n"
     "    document.close();\n"
     "    return true;\n"
     "  }\n\n"
     "  private stop() {\n",
     "private irisStartRunner3d(): boolean {", "start method")

# --- browser: error page exempt from the per-site WebGL block ---
b = "chrome/browser/chrome_content_browser_client.cc"
edit(b, "        IrisWebGLAllowed(web_contents, web_contents->GetLastCommittedURL());\n",
     "        (IrisWebGLAllowed(web_contents, web_contents->GetLastCommittedURL()) ||\n"
     "         // The offline / chrome://dino page runs only Iris's own game\n"
     "         // (apply-iris-runner.sh; jegly 2026-10-10).\n"
     "         web_contents->GetPrimaryMainFrame()->IsErrorDocument());\n",
     "web_contents->GetPrimaryMainFrame()->IsErrorDocument());", "WebGL on the offline page")
PY
echo "=== offline game (RUNNER) complete ==="
