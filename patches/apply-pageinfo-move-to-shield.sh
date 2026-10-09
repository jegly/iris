#!/usr/bin/env bash
# Iris — desktop Page Info: the Iris per-site controls moved into the toolbar shield panel (jegly 2026-10-09: "maybe
# everything in here should go under the shield so it's in one place"; verified against 156.0.8078.11).
# The shield panel (iris_toolbar_buttons.cc) now has: ads and trackers, cross-site cookies, JavaScript, WebGL, Google
# sign-in prompts, "forget this site", canvas/audio reading, browser identity and the TLS connection details. So on
# DESKTOP the Page Info popup no longer shows:
#   - the "Intrusive ads", "WebGL" and "Google sign-in prompts" permission rows   (PageInfo::ShouldShowPermission)
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
V = "chrome/browser/ui/views/page_info/"
edit(V + "page_info_main_view.cc",
     "  if (presenter_->iris_web_contents() &&\n      presenter_->site_url().SchemeIsHTTPOrHTTPS()) {\n    site_settings_view_->AddChildView(std::make_unique<IrisIdentityButton>(",
     "  // (Moved to the toolbar shield panel: apply-pageinfo-move-to-shield.sh.)\n"
     "  if (false && presenter_->iris_web_contents() &&\n      presenter_->site_url().SchemeIsHTTPOrHTTPS()) {\n    site_settings_view_->AddChildView(std::make_unique<IrisIdentityButton>(",
     "if (false && presenter_->iris_web_contents()", "hide browser identity row")
edit(V + "page_info_cookies_content_view.cc",
     "  AddIrisForgetSiteRow();  // Iris (B6)\n\n#if BUILDFLAG(IS_CHROMEOS)",
     "  if (false) {  // moved to the toolbar shield panel (apply-pageinfo-move-to-shield.sh)\n"
     "    AddIrisForgetSiteRow();  // Iris (B6)\n  }\n\n#if BUILDFLAG(IS_CHROMEOS)",
     "if (false) {  // moved to the toolbar shield panel", "hide forget-site row")
edit(V + "page_info_security_content_view.cc",
     "  if (identity_info.certificate) {\n    std::u16string iris_tls =",
     "  // (Moved to the toolbar shield panel: apply-pageinfo-move-to-shield.sh.)\n"
     "  if (false && identity_info.certificate) {\n    std::u16string iris_tls =",
     "if (false && identity_info.certificate)", "hide TLS details block")
PY
echo "=== Page Info items moved to the shield complete ==="
