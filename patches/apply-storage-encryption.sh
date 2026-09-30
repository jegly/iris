#!/usr/bin/env bash
# Iris — bookmarks + open tabs/session files: ENCRYPTED ONLY (jegly 2026-09-30, verified against this checkout).
# Upstream has kEncryptBookmarks + kEncryptSessionStorage ENABLED but at stage "write_both_read_only_clear": an encrypted
# copy AND a plain-text copy are written and only the plain text is read -> no protection at rest. Move both to the
# final upstream stage: write only the encrypted file, read it, and delete the leftover plain-text file after the first
# successful encrypted load (components/bookmarks/common/bookmark_features.cc, components/sessions/core/
# command_storage_manager.cc). Key = os_crypt_async: the Iris passphrase key when the lock is on (apply-app-lock.sh).
# NOTE: the plain-text file is deleted normally, not wiped (SSD blocks may keep it until reused) -> full-disk encryption.
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import re, sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
FINAL = {
  "components/bookmarks/common/bookmark_features.cc":
    ("kBookmarkEncryptionStageParam", "write_only_encrypted_read_prefer_encrypted"),
  "components/sessions/core/command_storage_features.cc":
    None,
}
# the session stage string lives in a constant; read it so we never hard-code a wrong value
import glob
txt = "".join(open(f).read() for f in glob.glob("components/sessions/core/*.cc") + glob.glob("components/sessions/core/*.h"))
m = re.search(r'kEncryptSessionStorageStageWriteEncryptedReadPreferEncrypted\[\]\s*=\s*"([^"]+)"', txt)
if not m: die("session final-stage constant not found (drift?)")
FINAL["components/sessions/core/command_storage_features.cc"] = ("kEncryptSessionStorageStageParam", m.group(1))
for p, (param, final) in FINAL.items():
    s = open(p).read()
    rx = re.compile(r'(BASE_FEATURE_PARAM\(std::string,\s*' + param + r',\s*&k\w+,\s*"stage",\s*)"([^"]*)"\);')
    hit = rx.search(s)
    if not hit: die("%s: %s declaration not found (drift?)" % (p, param))
    if hit.group(2) == final: print("SKIP already applied: %s (%s)" % (p, final)); continue
    if hit.group(2) != "write_both_read_only_clear": die("%s: unexpected default stage %r (drift?)" % (p, hit.group(2)))
    s = s[:hit.start()] + hit.group(1) + '"' + final + '");  // Iris: encrypted only' + s[hit.end():]
    open(p, "w").write(s); print("OK   %s : stage -> %s" % (p, final))
for p, f in [("components/bookmarks/common/bookmark_features.cc", "BASE_FEATURE(kEncryptBookmarks, base::FEATURE_ENABLED_BY_DEFAULT);"),
             ("components/sessions/core/command_storage_features.cc", "BASE_FEATURE(kEncryptSessionStorage, base::FEATURE_ENABLED_BY_DEFAULT);")]:
    if f not in open(p).read(): die("%s: feature no longer enabled by default upstream (guard)" % p)
PY
echo "=== storage encryption (bookmarks + sessions) complete ==="
