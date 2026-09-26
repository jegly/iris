# Iris — verification & config-integrity tooling

Two of the four "new features" (2026-09-25), both pure tooling — no Chromium build required.
All four scripts are copy-tested (gen → verify → tamper-detected). Requires `bash`, `coreutils`
(sha256sum/sha512sum), and `gpg` for the signing/authenticity steps.

## Feature 3 — Reproducible-build / release verification
Lets a user confirm the Iris binary they run is byte-identical to what jegly released, and (with a
signature) that jegly released it.

- `iris-gen-hashes.sh <artifact>...` — MAINTAINER: writes `SHA256SUMS` + `SHA512SUMS` over the
  release artifacts (deb/snap/apk/chrome). Prints the GPG command to sign `SHA256SUMS` (never
  touches your key itself).
- `iris-verify.sh <downloaded-artifact>` — USER: (1) verifies `SHA256SUMS.asc` is jegly's signature
  over `SHA256SUMS`, then (2) checks the artifact's SHA-256 against that trusted list. `SKIP_SIG=1`
  does integrity-only (not recommended — no authenticity).

Release page should carry: the artifact(s), `SHA256SUMS`, `SHA256SUMS.asc`, and jegly's public key.

### Honest scope
This is **artifact verification** — the property that actually protects users from tampered/MITM'd
downloads, and it's deliverable now. It is **NOT** full **bit-for-bit reproducible builds** (an
independent party rebuilding from source and getting identical bits). That's a separate, large effort:
pinned clang/rustc toolchain, identical checkout paths, stripped build-ids/timestamps, deterministic
archive metadata, `SOURCE_DATE_EPOCH`, etc. Tracked as a future goal — not claimed here.

## Feature 4 — Configuration integrity check
Detects if Iris's launch flags or policy files were modified externally, and shows the user exactly
what changed (file hashes + a human-readable flag diff).

- `iris-gen-config-manifest.sh <launcher> [policy-file...] > iris-config.manifest` — MAINTAINER:
  records known-good sha256 of the launcher + policy files, plus the launcher's `--flag` set
  (comments excluded). Prints the GPG sign command.
- `iris-config-check.sh <manifest>` — RUNTIME: re-hashes tracked files + re-parses the launcher's
  flags, prints a WARNING banner listing MODIFIED/MISSING files and ADDED/REMOVED flags. Exit 0 =
  match, 3 = drift. `IRIS_CONFIG_ENFORCE=1` makes drift refuse launch; `IRIS_CONFIG_VERBOSE=1`
  prints an OK line on success (silent by default). `SKIP_SIG=1` skips the manifest-signature check.

The launcher (`../launcher/iris-launcher`) calls the checker on startup if the checker + manifest are
installed beside it (`IRIS_MANIFEST` / `IRIS_CHECK` override the paths). Warn-only unless
`IRIS_CONFIG_ENFORCE=1`.

### Honest scope
This is a **tripwire, not tamper-proofing**: an attacker who can rewrite the launcher can also rewrite
the manifest and the checker. Its value is catching accidental drift, a bad package/update, or
other software quietly weakening the config — and giving the user visibility. Strengthen it by
GPG-signing the manifest (`iris-config.manifest.asc`, verified first) and/or shipping the manifest on
read-only/immutable media.

## Release-time flow (sketch)
```
# after building the deb/snap/apk:
verify/iris-gen-hashes.sh iris_*.deb iris_*.snap ChromePublic.apk
gpg --armor --detach-sign -o SHA256SUMS.asc SHA256SUMS

# per package, record the installed launcher + policy baseline:
verify/iris-gen-config-manifest.sh /opt/iris/iris-launcher /etc/iris/policies/*.json > iris-config.manifest
gpg --armor --detach-sign -o iris-config.manifest.asc iris-config.manifest
# ship iris-config.manifest(.asc) + iris-config-check.sh beside the launcher.
```
