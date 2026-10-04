#!/usr/bin/env bash
# Iris — chrome://flags says what "Default" means: "Default (Enabled)" / "Default (Disabled)" (jegly 2026-10-04;
# verified against the 156.0.8073.0 and 156.0.8078.9 sources).
# Why: Iris changes many feature defaults in code (e.g. apply-flags-group5.sh turns Rust ICO/JPEG decoding ON), but
# chrome://flags only showed "Default", so users couldn't tell those were already on and set them by hand.
# How (components/webui/flags/flags_state.cc, CreateOptionsData): for feature flags (FEATURE_VALUE /
# FEATURE_WITH_PARAMS_VALUE) the first option's label gets a suffix:
#   - while "Default" is the selected option: the LIVE state, base::FeatureList::IsEnabled(feature), which includes
#     Iris's code defaults and its compiled-in --enable/--disable-features switches;
#   - otherwise: the feature's built-in default (base::Feature::default_state). Country-specific defaults get no
#     suffix (they depend on the country).
# Other flag types (multi-value, enable/disable switches) are unchanged. Desktop + Android (same flags page code).
# Chrome Labs (toolbar) uses FeatureEntry::DescriptionForOption directly and is unchanged.
# English-only suffix (no new grit string), like "Default"/"Enabled" in feature_entry.cc, which are not translated
# either.
# STATUS 2026-10-04: copy-tested only, NOT compile-proven (flags_state.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
p = "components/webui/flags/flags_state.cc"
s = open(p).read()
MARK = "iris_default_suffix"
if MARK in s:
    print("SKIP already applied: %s" % p); sys.exit(0)
inc = '#include <memory>\n'
loop = ("  base::ListValue result;\n"
        "  for (int i = 0; i < entry.NumOptions(); ++i) {\n"
        "    base::DictValue dict;\n"
        "    std::string name = entry.NameForOption(i);\n"
        "    dict.Set(\"selected\", enabled_entries.contains(name));\n"
        "    dict.Set(\"internal_name\", std::move(name));\n"
        "    dict.Set(\"description\", entry.DescriptionForOption(i));\n"
        "    result.Append(std::move(dict));\n"
        "  }\n")
for a, what in ((inc, "<memory> include"), (loop, "CreateOptionsData option loop")):
    if s.count(a) != 1: die("%s: %s not found exactly once (drift?)" % (p, what))
s = s.replace(inc, inc + "#include <optional>  // Iris\n", 1)
new_loop = (
    "  // Iris: say what \"Default\" means for feature flags (Iris changes many\n"
    "  // defaults): \"Default (Enabled)\" / \"Default (Disabled)\". While Default is\n"
    "  // selected this is the live state (Iris's code defaults and compiled-in\n"
    "  // switches included); otherwise the feature's built-in default.\n"
    "  std::u16string iris_default_suffix;\n"
    "  if ((entry.type == FeatureEntry::FEATURE_VALUE ||\n"
    "       entry.type == FeatureEntry::FEATURE_WITH_PARAMS_VALUE) &&\n"
    "      entry.feature.feature) {\n"
    "    bool default_selected = true;\n"
    "    for (int i = 1; i < entry.NumOptions(); ++i) {\n"
    "      if (enabled_entries.contains(entry.NameForOption(i))) {\n"
    "        default_selected = false;\n"
    "      }\n"
    "    }\n"
    "    std::optional<bool> enabled;\n"
    "    if (default_selected) {\n"
    "      enabled = base::FeatureList::IsEnabled(*entry.feature.feature);\n"
    "    } else if (entry.feature.feature->default_state ==\n"
    "               base::FEATURE_ENABLED_BY_DEFAULT) {\n"
    "      enabled = true;\n"
    "    } else if (entry.feature.feature->default_state ==\n"
    "               base::FEATURE_DISABLED_BY_DEFAULT) {\n"
    "      enabled = false;\n"
    "    }\n"
    "    if (enabled.has_value()) {\n"
    "      iris_default_suffix = *enabled ? u\" (Enabled)\" : u\" (Disabled)\";\n"
    "    }\n"
    "  }\n"
    + loop.replace(
        "    dict.Set(\"description\", entry.DescriptionForOption(i));\n",
        "    dict.Set(\"description\", i == 0 ? entry.DescriptionForOption(i) +\n"
        "                                         iris_default_suffix\n"
        "                                   : entry.DescriptionForOption(i));\n"))
s = s.replace(loop, new_loop, 1)
open(p, "w").write(s)
print("OK   %s : 'Default (Enabled)' / 'Default (Disabled)' for feature flags" % p)
PY
echo "=== flags default state complete ==="
