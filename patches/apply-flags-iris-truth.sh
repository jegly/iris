#!/usr/bin/env bash
# Iris — chrome://flags shows what is really on or off (jegly 2026-10-11: "flags should show what flags r actually on or
# off"; "not sure why it shows thing as being enabled that dont exist in iris ... example webrtc"; verified against
# 156.0.8078.11). Follows apply-flags-default-state.sh, which labels FEATURE rows "Default (Enabled)/(Disabled)".
#  1. Switch rows (SINGLE_VALUE, SINGLE_DISABLE_VALUE, ORIGIN_LIST_VALUE, STRING_VALUE) had only "Disabled / Enabled",
#     with no sign which one is the default. Their default choice now reads "Default (Disabled)" or
#     "Default (Enabled)". While the default is selected, the state is read from the running browser's command line,
#     so a switch Iris passes itself shows as on. (components/webui/flags/flags_state.cc sends iris_default_option +
#     iris_default_label; components/webui/flags/resources/experiment{.ts,.html.ts} use them.)
#  2. Rows for things Iris removed are not listed (chrome/browser/about_flags.cc ShouldSkipConditionalFeatureEntry).
#     WebRTC and camera/microphone for websites are gone (apply-webrtc-off.sh, apply-webrtc-media-off.sh), but the
#     WebRTC code stays compiled in, so its tuning flags still read "Default (Enabled)". Listed below; extend the list
#     when another removed area is audited. A value saved for a hidden row before this patch still applies until
#     "Reset all" (harmless here: nothing can reach the code).
# English-only labels (no new grit strings), like apply-flags-default-state.sh.
# Needs apply-flags-default-state.sh (anchor) and apply-flags-site-isolation.sh is independent.
# STATUS 2026-10-11: copy-tested only, NOT compile-proven (flags_state.o, about_flags.o, flags resources).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

def edit(p, old, new, marker, what):
    s = open(p).read()
    if marker in s:
        print("SKIP already applied: %s (%s)" % (p, what)); return
    if s.count(old) != 1:
        die("%s: anchor for %s found %d times (drift?)" % (p, what, s.count(old)))
    open(p, "w").write(s.replace(old, new))
    print("OK   %s : %s" % (p, what))

# 1a. flags_state.cc: default label for switch rows.
p = "components/webui/flags/flags_state.cc"
if "iris_default_suffix" not in open(p).read():
    die("%s: apply-flags-default-state.sh not applied" % p)
OLD = ('    bool is_default_value = IsDefaultValue(entry, enabled_entries);\n'
       '    data.Set("is_default", is_default_value);\n')
NEW = OLD + (
    '    // Iris: the default choice of a switch row says what it means:\n'
    '    // "Default (Disabled)" / "Default (Enabled)" (apply-flags-iris-truth.sh).\n'
    '    // While it is selected, the state comes from this browser\'s command\n'
    '    // line, so switches Iris passes itself show as on.\n'
    '    if (entry.type == FeatureEntry::SINGLE_VALUE ||\n'
    '        entry.type == FeatureEntry::SINGLE_DISABLE_VALUE ||\n'
    '        entry.type == FeatureEntry::ORIGIN_LIST_VALUE ||\n'
    '        entry.type == FeatureEntry::STRING_VALUE) {\n'
    '      const bool iris_switch_on =\n'
    '          is_default_value && entry.switches.command_line_switch &&\n'
    '          base::CommandLine::ForCurrentProcess()->HasSwitch(\n'
    '              entry.switches.command_line_switch);\n'
    '      if (entry.type == FeatureEntry::SINGLE_DISABLE_VALUE) {\n'
    '        // The switch turns something off; no switch = Enabled.\n'
    '        data.Set("iris_default_option", "enabled");\n'
    '        data.Set("iris_default_label", iris_switch_on ? "Default (Disabled)"\n'
    '                                                      : "Default (Enabled)");\n'
    '      } else {\n'
    '        data.Set("iris_default_option", "disabled");\n'
    '        data.Set("iris_default_label", iris_switch_on ? "Default (Enabled)"\n'
    '                                                      : "Default (Disabled)");\n'
    '      }\n'
    '    }\n')
edit(p, OLD, NEW, "iris_default_option", "switch rows: Default (Enabled)/(Disabled)")

# 1b. Front end: the interface, a label helper, the template.
p = "components/webui/flags/resources/flags_browser_proxy.ts"
OLD = ('  string_value?: string;\n')
NEW = OLD + ('  // Iris (apply-flags-iris-truth.sh): switch rows only.\n'
             '  iris_default_option?: string;\n'
             '  iris_default_label?: string;\n')
edit(p, OLD, NEW, "iris_default_option", "Feature: iris_default_option/label")

p = "components/webui/flags/resources/experiment.ts"
OLD = ('  protected showMultiValueSelect_(): boolean {\n')
NEW = ('  // Iris (apply-flags-iris-truth.sh): the default choice of a switch row\n'
       '  // reads "Default (Disabled)" / "Default (Enabled)".\n'
       '  protected irisEnableDisableLabel_(value: string): string {\n'
       '    if (this.feature_.iris_default_label &&\n'
       '        this.feature_.iris_default_option === value) {\n'
       '      return this.feature_.iris_default_label;\n'
       '    }\n'
       '    return loadTimeData.getString(value);\n'
       '  }\n'
       '\n') + OLD
edit(p, OLD, NEW, "irisEnableDisableLabel_", "irisEnableDisableLabel_()")

p = "components/webui/flags/resources/experiment.html.ts"
OLD = ('          <option value="disabled" .selected="${!this.feature_.enabled}">\n'
       '            $i18n{disabled}\n'
       '          </option>\n'
       '          <option value="enabled" .selected="${this.feature_.enabled}">\n'
       '            $i18n{enabled}\n'
       '          </option>\n')
NEW = ('          <option value="disabled" .selected="${!this.feature_.enabled}">\n'
       '            ${this.irisEnableDisableLabel_(\'disabled\')}\n'
       '          </option>\n'
       '          <option value="enabled" .selected="${this.feature_.enabled}">\n'
       '            ${this.irisEnableDisableLabel_(\'enabled\')}\n'
       '          </option>\n')
edit(p, OLD, NEW, "irisEnableDisableLabel_", "switch-row labels")

# 2. about_flags.cc: no rows for removed things.
p = "chrome/browser/about_flags.cc"
OLD = ('bool ShouldSkipConditionalFeatureEntry(const flags_ui::FlagsStorage* storage,\n'
       '                                       const FeatureEntry& entry) {\n')
NEW = OLD + (
    '  // Iris: no rows for things Iris removed (apply-flags-iris-truth.sh). Their\n'
    '  // code is still compiled in but websites can no longer reach it, so the\n'
    '  // rows read "Default (Enabled)" for something that is not there.\n'
    '  static constexpr const char* kIrisRemovedFlags[] = {\n'
    '      // WebRTC and camera/microphone for websites (apply-webrtc-off.sh,\n'
    '      // apply-webrtc-media-off.sh, CameraAndMicrophoneElements in\n'
    '      // apply-default-switches.sh).\n'
    '      "webrtc-hw-decoding",\n'
    '      "webrtc-hw-encoding",\n'
    '      "webrtc-pqc-for-dtls",\n'
    '      "enable-webrtc-allow-input-volume-adjustment",\n'
    '      "enable-webrtc-apm-downmix-capture-audio-method",\n'
    '      "enable-webrtc-hide-local-ips-with-mdns",\n'
    '      "enable-webrtc-use-min-max-vea-dimensions",\n'
    '      "enable-webrtc-pipewire-camera",\n'
    '      "webrtc-wgc-require-border",\n'
    '      "local-network-access-check-webrtc",\n'
    '      "use-fake-device-for-media-stream",\n'
    '      "camera-and-microphone-elements",\n'
    '  };\n'
    '  for (const char* iris_name : kIrisRemovedFlags) {\n'
    '    if (std::string_view(iris_name) == entry.internal_name) {\n'
    '      return true;\n'
    '    }\n'
    '  }\n'
    '\n')
edit(p, OLD, NEW, "kIrisRemovedFlags", "removed-feature rows hidden")
PY
echo "=== flags truth complete ==="
