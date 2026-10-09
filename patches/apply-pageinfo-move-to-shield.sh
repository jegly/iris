#!/usr/bin/env bash
# Iris — desktop Page Info: the Iris per-site controls moved into the toolbar shield panel (jegly 2026-10-09: "maybe
# everything in here should go under the shield so it's in one place"; verified against 156.0.8078.11).
# The shield panel (iris_toolbar_buttons.cc) now has: ads and trackers, cross-site cookies, JavaScript, WebGL, Google
# sign-in prompts, "forget this site", canvas/audio reading, browser identity and the TLS connection details. So on
# DESKTOP the Page Info popup no longer shows:
#   - the "Intrusive ads", "JavaScript", "WebGL" and "Google sign-in prompts" rows (PageInfo::ShouldShowPermission)
#   - the "Browser identity" row                                                 (page_info_main_view.cc)
#   - the "Forget this site" toggle on the cookies page                         (page_info_cookies_content_view.cc)
#   - the TLS "Connection details" block on "Connection is secure"              (page_info_security_content_view.cc)
# Chromium's own items stay (certificate, cookies and site data, permissions such as camera, Site settings).
# ANDROID IS UNCHANGED: components/page_info is shared, so the row filter is under #if !BUILDFLAG(IS_ANDROID); the other
# three files are desktop-only views. Android has no shield panel, so its Page Info keeps these rows.
# The removed UI code stays in the files (unused) so apply-page-info-*.sh and apply-forget-site.sh still apply cleanly.
# Needs those scripts first. STATUS 2026-10-09: copy-tested only, NOT compile-proven.
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
edit("components/page_info/page_info.cc",
     "  // Iris: its per-site switches are always offered on the site's Page Info.\n",
     "  // Iris (desktop): these per-site switches live in the toolbar shield panel\n"
     "  // (apply-pageinfo-move-to-shield.sh). Android keeps them here.\n"
     "#if !BUILDFLAG(IS_ANDROID)\n"
     "  if (info.type == ContentSettingsType::ADS ||\n"
     "      info.type == ContentSettingsType::IRIS_WEBGL ||\n"
     "      info.type == ContentSettingsType::IRIS_GOOGLE_SIGNIN) {\n"
     "    return false;\n"
     "  }\n"
     "#endif\n\n"
     "  // Iris: its per-site switches are always offered on the site's Page Info.\n",
     "apply-pageinfo-move-to-shield.sh", "hide ads / WebGL / sign-in rows (desktop)")
# JavaScript too: Chromium adds a JavaScript row once a site has its own setting; the shield and the </> button own it.
edit("components/page_info/page_info.cc",
     "  if (info.type == ContentSettingsType::ADS ||\n      info.type == ContentSettingsType::IRIS_WEBGL ||\n",
     "  if (info.type == ContentSettingsType::ADS ||\n"
     "      info.type == ContentSettingsType::JAVASCRIPT ||  // Iris: in the shield\n"
     "      info.type == ContentSettingsType::IRIS_WEBGL ||\n",
     "ContentSettingsType::JAVASCRIPT ||  // Iris: in the shield", "hide JavaScript row (desktop)")
V = "chrome/browser/ui/views/page_info/"
# The hidden blocks are compiled out with #if 0 (an "if (false ...)" is rejected by -Wunreachable-code). The original
# lines stay inside, so the markers of apply-page-info-identity / apply-forget-site / apply-page-info-tls still match.
# Trees patched by the first version of this script (if (false && ...)) are upgraded in place.
def hide(p, block_start, block, label):
    s = open(p).read()
    tag = "#if 0  // Iris: moved to the toolbar shield panel (apply-pageinfo-move-to-shield.sh)\n"
    if tag in s and block_start in s:
        print("SKIP already applied: %s (%s)" % (p, label)); return
    old_v1 = block.replace(block_start, block_start.replace("if (", "if (false && ", 1), 1)
    old_v1 = "  // (Moved to the toolbar shield panel: apply-pageinfo-move-to-shield.sh.)\n" + old_v1
    if s.count(old_v1) == 1:
        s = s.replace(old_v1, tag + block + "#endif\n", 1)
    elif s.count(block) == 1:
        s = s.replace(block, tag + block + "#endif\n", 1)
    else:
        die("%s: block for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s); print("OK   %s : %s" % (p, label))

hide(V + "page_info_main_view.cc",
     "  if (presenter_->iris_web_contents() &&",
     "  if (presenter_->iris_web_contents() &&\n"
     "      presenter_->site_url().SchemeIsHTTPOrHTTPS()) {\n"
     "    site_settings_view_->AddChildView(std::make_unique<IrisIdentityButton>(\n"
     "        presenter_->iris_web_contents(), presenter_->site_url()));\n"
     "  }\n", "hide browser identity row")
hide(V + "page_info_security_content_view.cc",
     "  if (identity_info.certificate) {\n    std::u16string iris_tls =",
     "  if (identity_info.certificate) {\n"
     "    std::u16string iris_tls =\n"
     "        iris::GetTlsDetailsText(presenter_->iris_web_contents());\n"
     "    if (!iris_tls.empty()) {\n"
     "      iris_tls_view_ = AddChildView(std::make_unique<SecurityInformationView>(\n"
     "          ChromeLayoutProvider::Get()\n"
     "              ->GetInsetsMetric(views::INSETS_DIALOG)\n"
     "              .left()));\n"
     "      iris_tls_view_->SetIcon(\n"
     "          PageInfoViewFactory::GetImageModel(vector_icons::kShieldIcon));\n"
     "      iris_tls_view_->SetSummary(u\"Connection details\",\n"
     "                                 views::style::STYLE_BODY_3_MEDIUM);\n"
     "      iris_tls_view_->SetDetails(iris_tls);\n"
     "    }\n"
     "  }\n", "hide TLS details block")
C = V + "page_info_cookies_content_view.cc"
s = open(C).read()
v1 = "  if (false) {  // moved to the toolbar shield panel (apply-pageinfo-move-to-shield.sh)\n    AddIrisForgetSiteRow();  // Iris (B6)\n  }\n"
call = "  AddIrisForgetSiteRow();  // Iris (B6)\n"
tag = "#if 0  // Iris: moved to the toolbar shield panel (apply-pageinfo-move-to-shield.sh)\n"
if tag in s:
    print("SKIP already applied: %s (hide forget-site row)" % C)
else:
    if s.count(v1) == 1: s = s.replace(v1, tag + call + "#endif\n", 1)
    elif s.count(call) == 1: s = s.replace(call, tag + call + "#endif\n", 1)
    else: die("%s: forget-site call not found exactly once (drift?)" % C)
    open(C, "w").write(s); print("OK   %s : hide forget-site row" % C)
PY
echo "=== Page Info items moved to the shield complete ==="
