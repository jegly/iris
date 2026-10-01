#!/usr/bin/env bash
# Iris — Android UI strings: "Chrome" -> "Iris" (jegly 2026-10-01: "About Chrome" etc. in the APK).
# Android's string files say "Chrome" literally (for Chromium builds too); app_name is already Iris
# (apply-rebrand-android.sh). Rewrites the visible English text of every message that mentions Chrome in the
# Android grd files below, and keeps translations working: grit message IDs are a fingerprint of the English
# text, so each changed message gets a new ID; for every language (.xtb) the old translation is copied to the new
# ID with the same brand rewrite (old entry kept, so identical text used by a kept message still resolves).
# Rules (English and translations, text only — never desc attributes, <ex> examples or placeholder tags):
#   "Google Chrome" -> "Iris"; "Chrome" -> "Iris" when no Latin letter/digit touches it (keeps ChromeOS,
#   Chromebook, Chromecast; works next to CJK text); "Chrome Web Store" is a store name -> unchanged.
#   Messages left alone on purpose: Google's legal ToS titles/links and the Web Store menu entry (KEEP below).
# Uses Chromium's own grit to compute IDs (same defines as the Android build). Translations that spell Chrome in
# another script get the new ID with their text unchanged (reported as "untouched").
# Guarded; idempotent (SKIP when already applied); fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import os, re, sys
sys.path.insert(0, "tools/grit")
from grit import grd_reader
from grit.node import message

GRDS = [
    "chrome/browser/ui/android/strings/android_chrome_strings.grd",
    "components/browser_ui/strings/android/browser_ui_strings.grd",
    "chrome/android/features/tab_ui/java/strings/android_chrome_tab_ui_strings.grd",
    "chrome/browser/keyboard_accessory/android/internal/java/strings/android_keyboard_accessory_strings.grd",
]
KEEP = {
    "IDS_CHROME_ADDITIONAL_TERMS_OF_SERVICE_TITLE",                 # legal document title
    "IDS_LIGHTWEIGHT_FRE_ASSOCIATED_APP_TOS",                       # Google ToS links (account FRE)
    "IDS_LIGHTWEIGHT_FRE_ASSOCIATED_APP_TOS_AND_PRIVACY_CHILD_ACCOUNT",
    "IDS_MENU_CHROME_WEBSTORE",                                     # store name
}
# Same grit defines as the Android build (out/Android toolchain.ninja, grit action for these grds).
D = ("chrome_root_store_cert_management_ui=false enable_arcore=false enable_cardboard=false enable_compose=false "
     "enable_dice_support=false enable_extensions=false enable_extensions_core=false "
     "enable_hangout_services_extension=false enable_openxr=false enable_pdf=false enable_pdf_save_to_drive=false "
     "enable_printing=true enable_print_preview=false enable_screen_capture=true enable_supervised_users=true "
     "enable_vr=false enable_webui_certificate_viewer=false enable_webui_contextual_tasks_composebox=true "
     "enable_webui_ntp=false _google_chrome=false _is_chrome_for_testing_branded=false is_desktop_android=false "
     "is_official_build=true optimize_webui=true reven=false safe_browsing_mode=2 toolkit_views=false use_aura=false "
     "use_nss_certs=false use_ozone=false use_titlecase=false webnn_enable_graph_dump=false")
DEFS = {k: {"true": True, "false": False}.get(v, int(v) if v.isdigit() else v)
        for k, v in (x.split("=") for x in D.split())}

def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)

BRAND = re.compile(r"Google Chrome|(?<![A-Za-z0-9])Chrome(?![A-Za-z0-9])")
def rebrand_text(t):
    t = t.replace("Chrome Web Store", "\0WS\0")
    t = BRAND.sub("Iris", t)
    return t.replace("\0WS\0", "Chrome Web Store")
def rebrand_markup(body, protect_ex):
    # Only text between tags; <ex>...</ex> examples kept verbatim (grd); tags/attributes never touched.
    parts = re.split(r"(<ex>.*?</ex>|<[^>]+>)" if protect_ex else r"(<[^>]+>)", body, flags=re.S)
    return "".join(p if (p.startswith("<")) else rebrand_text(p) for p in parts)
def visible(body): return re.sub(r"<ex>.*?</ex>|<[^>]+>", "", body, flags=re.S)
def needs(body): return bool(BRAND.search(visible(body).replace("Chrome Web Store", "")))

MSG = re.compile(r'(<message\s+name\s*=\s*"(IDS_[A-Z0-9_]+)"[^>]*>)(.*?)(</message>)', re.S)  # upstream has 'name ="'

def ids(grd):
    res = grd_reader.Parse(grd, debug=False, defines=DEFS, target_platform="android")
    out = {}
    for n in res.Preorder():
        if isinstance(n, message.MessageNode):
            out.setdefault(n.attrs["name"], set()).add(n.GetCliques()[0].GetId())
    return out

def parts_of(grd):
    d = os.path.dirname(grd)
    return [os.path.normpath(os.path.join(d, f)) for f in re.findall(r'<part file="([^"]+)"', open(grd).read())]

def xtbs_of(grd):
    d = os.path.dirname(grd)
    return [os.path.normpath(os.path.join(d, f))
            for f in re.findall(r'<file path="([^"]+\.xtb)"', open(grd).read())]

total_msgs = total_tr = total_untouched = 0
for grd in GRDS:
    if not os.path.isfile(grd): die("missing " + grd)
    files = [grd] + parts_of(grd)
    pending = [(f, n) for f in files for (_, n, b, _) in MSG.findall(open(f).read()) if n not in KEEP and needs(b)]
    if not pending:
        print("SKIP already applied: %s" % grd); continue
    before = ids(grd)
    changed = set()
    for f in files:
        s = open(f).read()
        def sub(m):
            if m.group(2) in KEEP or not needs(m.group(3)): return m.group(0)
            changed.add(m.group(2))
            return m.group(1) + rebrand_markup(m.group(3), True) + m.group(4)
        s2 = MSG.sub(sub, s)
        if s2 != s: open(f, "w").write(s2)
    after = ids(grd)
    remap = {}
    for n in changed:
        b, a = before.get(n, set()), after.get(n, set())
        if len(b) != 1 or len(a) != 1: die("%s: %s has %d/%d variants; extend the script" % (grd, n, len(b), len(a)))
        (o,), (nw,) = b, a
        if o != nw: remap[o] = nw
    tr = untouched = 0
    for x in xtbs_of(grd):
        s = open(x).read(); add = []
        for o, nw in remap.items():
            if ('<translation id="%s">' % nw) in s: continue
            m = re.search(r'<translation id="%s">(.*?)</translation>' % o, s, re.S)
            if not m: continue
            t = rebrand_markup(m.group(1), False)
            if t == m.group(1): untouched += 1
            add.append((m.end(), '\n<translation id="%s">%s</translation>' % (nw, t)))
        for pos, line in sorted(add, reverse=True):
            s = s[:pos] + line + s[pos:]
        if add: open(x, "w").write(s); tr += len(add)
    total_msgs += len(changed); total_tr += tr; total_untouched += untouched
    print("OK   %s : %d messages -> Iris, %d translations re-keyed (%d kept their own spelling)"
          % (grd, len(changed), tr, untouched))
print("=== Android strings: %d messages, %d translations ===" % (total_msgs, total_tr))
PY
