#!/usr/bin/env bash
# Iris — .deb: no Google apt repository, no Google signing key, no daily cron job (found 2026-10-02 in the -3 install
# test; -1 and -2 shipped it). Verified against this checkout.
# Upstream's Linux installer (chrome/installer/linux, kept for Chromium branding too) makes the package postinst:
#   - write Google's Linux package-signing key to /usr/share/keyrings/iris-browser.gpg (fpr EB4C1BFD…D38B4796),
#   - add https://dl.google.com/linux/chrome-stable/deb/ as /etc/apt/sources.list.d/iris-browser.sources,
#   - write /etc/default/iris-browser (repo_add_once / repo_reenable_on_distupgrade),
# and ships /etc/cron.daily/iris-browser (-> <install dir>/cron/iris-browser) that keeps the repo configured.
# Result: every `apt update` contacts Google and Google's repo is trusted to install packages as root.
# Here:
#   debian/postinst  no longer includes common/apt.include (so no key data in the package) or calls install_key /
#                    install_deb822_sources; it REMOVES what -1/-2 installed (only our own files, checked by content).
#   debian/postrm    on purge, the same cleanup instead of apt.include.
#   debian/build.py  no cron file and no /etc/cron.daily link (dpkg removes the old link on upgrade: not a conffile).
# The snap was never affected (no postinst; snapcraft.yaml drops etc/cron.daily). Guarded; idempotent; fails on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC/chrome/installer/linux"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))

CLEANUP = r'''# Iris: no Google apt repository or signing key (apply-deb-no-google-repo.sh). Iris 156.0.8073.0-1/-2 installed
# them (upstream Chrome installer); remove them, touching only files that are ours by name AND content.
iris_remove_google_repo() {
  IRIS_SOURCES_DIR="/etc/apt/sources.list.d"
  if command -v apt-config >/dev/null 2>&1; then
    eval $(apt-config shell IRIS_SOURCES_DIR 'Dir::Etc::sourceparts/d')
  fi
  IRIS_SOURCES="${IRIS_SOURCES_DIR%/}/@@PACKAGE.sources"
  if [ -f "$IRIS_SOURCES" ] && grep -q "dl.google.com/linux/chrome" "$IRIS_SOURCES"; then
    rm -f "$IRIS_SOURCES"
  fi
  IRIS_LIST="${IRIS_SOURCES_DIR%/}/@@PACKAGE.list"
  if [ -f "$IRIS_LIST" ] && ! grep -v -E "^[[:space:]]*(#|$)" "$IRIS_LIST" | grep -v -q "dl.google.com/linux/chrome"; then
    rm -f "$IRIS_LIST"
  fi
  rm -f "/usr/share/keyrings/@@PACKAGE.gpg"
  IRIS_DEFAULTS="/etc/default/@@PACKAGE"
  if [ -f "$IRIS_DEFAULTS" ] && ! grep -v -q -E "^[[:space:]]*(repo_add_once|repo_reenable_on_distupgrade)=" "$IRIS_DEFAULTS"; then
    rm -f "$IRIS_DEFAULTS"
  fi
}
'''

p = "debian/postinst"
edit(p, "@@include@@../common/apt.include\n\n", CLEANUP + "\n", "iris_remove_google_repo() {", "cleanup function")
edit(p, "## MAIN ##\ninstall_key\ninstall_deb822_sources\nremove_legacy_list\nremove_legacy_key\n",
     "## MAIN ##\niris_remove_google_repo  # Iris\n", "iris_remove_google_repo  # Iris", "no repo or key")

p = "debian/postrm"
edit(p, "@@include@@../common/apt.include\n\n", CLEANUP + "\n", "iris_remove_google_repo() {", "cleanup function")
old = ('''# Only remove the defaults file if it is not empty. An empty file was probably
# put there by the sysadmin to disable automatic repository configuration, as
# per the instructions on the package download page.
if [ -s "$DEFAULTS_FILE" ]; then
  # Make sure the package defaults are removed before the repository config,
  # otherwise it could result in the repository config being removed, but the
  # package defaults remain and are set to not recreate the repository config.
  # In that case, future installs won't recreate it and won't get auto-updated.
  rm "$DEFAULTS_FILE" || exit 1
fi
# Remove any Google repository added by the package.
clean_sources_lists
uninstall_key
''')
edit(p, old, "iris_remove_google_repo  # Iris\n", "iris_remove_google_repo  # Iris", "purge cleanup")

p = "debian/build.py"
old = '''        cron_dir = install_dir / "cron"
        cron_dir.mkdir(parents=True, exist_ok=True)
        cron_dir.chmod(installer.StandardPermissions.EXECUTABLE)

        cron_file = cron_dir / config.info_vars["PACKAGE"]
        installer.process_template(
            output_dir / "installer/common/repo.cron",
            cron_file,
            config.get_template_context(),
        )
        cron_file.chmod(installer.StandardPermissions.EXECUTABLE)

        cron_daily_link = (
            staging_dir / "etc/cron.daily" / config.info_vars["PACKAGE"]
        )
        if cron_daily_link.is_symlink() or cron_daily_link.exists():
            cron_daily_link.unlink()
        os.symlink(
            os.path.join(
                config.info_vars["INSTALLDIR"],
                "cron",
                config.info_vars["PACKAGE"],
            ),
            cron_daily_link,
        )
'''
edit(p, old, "        # Iris: no repo cron job (it kept Google's apt repository configured).\n",
     "# Iris: no repo cron job", "no cron job")
old = '''        (staging_dir / "etc/cron.daily").mkdir(parents=True, exist_ok=True)
        (staging_dir / "etc/cron.daily").chmod(
            installer.StandardPermissions.EXECUTABLE
        )
'''
s = open(p).read()  # removal: no marker of its own, so guard on the cron edit above
if old in s:
    open(p, "w").write(s.replace(old, "", 1)); print("OK   %s : no cron.daily dir" % p)
elif "# Iris: no repo cron job" in s:
    print("SKIP already applied: %s (no cron.daily dir)" % p)
else:
    die("%s: cron.daily anchor not found (drift?)" % p)
PY
echo "=== .deb without Google apt repo / key / cron complete ==="
