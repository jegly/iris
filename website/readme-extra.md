## Verify your download

Every release comes with `SHA256SUMS`, signed twice (ML-DSA-87 and Ed25519), and my public keys.

```bash
openssl pkeyutl -verify -pubin -inkey jegly-mldsa87.pub.pem -rawin -in SHA256SUMS -sigfile SHA256SUMS.mldsa87.sig
gpg --import jegly.asc && gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

The ML-DSA-87 check needs OpenSSL 3.5 or newer. `packaging/verify/iris-verify.sh <file>` runs all three and makes
sure the keys are mine. My keys are also in `keys/`:

- ML-DSA-87: `sha256sum jegly-mldsa87.pub.pem` = `3c57473c5b1158c5854d97072db1aca4364c75145aef46130f465a7969e5f91f`
- GPG: `6B84 F8EB 46B9 B634 0BF4 A0E1 A5A5 6CEB 0244 5D37`

## Building from source

Iris is a set of small, guarded patch scripts applied to an upstream Chromium checkout, plus build configs.

1. Get Chromium (`depot_tools`, `fetch chromium`) and check out the base commit
   `90b94f20cbf6d512624a5ab4ef5920311d50c7ec` (Chromium 156.0.8073.0).
2. The ad-block ruleset is included in `adblock/dist/`. `adblock/build-ruleset.sh` rebuilds it from fresh lists.
3. Apply everything: `patches/apply-all.sh ~/path/to/chromium/src`. Each script checks the code it changes and
   stops with an error if upstream has drifted; re-running is safe.
4. Configure and build:
   ```bash
   mkdir -p out/Linux && cp build/args-linux.gn out/Linux/args.gn && gn gen out/Linux
   autoninja -C out/Linux -k 0 chrome chrome/installer/linux:stable_deb
   ```
   Android (`build/args-android.gn`) isn't released yet.

`build/args-dev.gn` is a faster non-official config for development. To check a build, run `python3 test/serve.py`
and open the self-test page in Iris.

## Repository layout

| Path | Contents |
|---|---|
| `patches/` | one script per change; `apply-all.sh` runs them in order; new source files in `patches/src/` |
| `build/` | gn args for Linux, Android and dev builds |
| `adblock/` | ruleset builder; bundled lists and their license |
| `packaging/` | .deb notes, snap, launcher, release verification tools |
| `branding/` | icons, orb logo, theme palettes |
| `website/` | the project website (`index.html`); `build-readme.py` turns it into this README, `make-banner.py` draws the banner |
| `test/` | self-test page for a built browser |

## Security notes

- The GPU process isn't sandboxed on Linux with Mesa drivers, same as stock Chromium. Web pages and the network
  service are.
- Ubuntu's default `ptrace_scope=1` stops other programs from reading Iris's memory.
- Without the app lock or a desktop keyring, stored data falls back to Chromium's built-in key. History and cache are
  never encrypted, so use full-disk encryption.

## Reporting problems

Bugs: [GitHub issues](https://github.com/jegly/iris/issues). Security issues: please report privately through
GitHub's *Report a vulnerability* (Security tab) rather than a public issue.

## Credits and licenses

- Chromium: BSD-3-Clause and the licenses of its third-party components (see `chrome://credits` in the browser).
- EasyList and EasyPrivacy filter lists: The EasyList authors, GPLv3+ / CC BY-SA 3.0
  (shipped as `/usr/share/doc/iris-browser-stable/filter-lists-LICENSE`).
- DotGothic16 font (Iris wordmark and Settings headers): The DotGothic16 Project Authors, SIL Open Font License 1.1
  (`website/fonts/OFL.txt`).
- IBM Plex Sans font (built-in pages): IBM Corp., SIL Open Font License 1.1.
- Catppuccin colour palette: the Catppuccin project, MIT.
- Iris patches and tooling: GPL-2.0-or-later (`LICENSE`). "Or later" because Chromium contains Apache-2.0
  components, which are compatible with GPL-3.0 but not GPL-2.0-only.

Iris is made by [jegly](https://github.com/jegly). It is based on Chromium and not affiliated with Google.
