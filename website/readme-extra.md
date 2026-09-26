## Verify your download

Each release carries `SHA256SUMS`, `SHA256SUMS.asc` (signed by jegly) and jegly's public key.

```bash
gpg --import jegly.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

Check the signature first, then the checksum. `packaging/verify/iris-verify.sh <file>` does both steps.
This proves the file is the one jegly published; it is not a reproducible-build guarantee.

## Building from source

Iris is a set of small, guarded patch scripts applied to an upstream Chromium checkout, plus build configs.

1. Get Chromium (`depot_tools`, `fetch chromium`) and check out the base commit in
   `patches/snapshot/*.base-commit` (currently `90b94f20cbf6d512624a5ab4ef5920311d50c7ec`).
2. Build the ad-block ruleset: `adblock/build-ruleset.sh` (downloads EasyList + EasyPrivacy, needs the
   `ruleset_converter` tool from `out/Default`).
3. Apply everything: `patches/apply-all.sh ~/path/to/chromium/src`. Each script checks the code it changes and
   stops with an error if upstream has drifted; re-running is safe.
4. Configure and build:
   ```bash
   cp build/args-linux.gn out/Linux/args.gn && gn gen out/Linux
   autoninja -C out/Linux chrome chrome/installer/linux:stable_deb
   ```
   Android: `build/args-android.gn` and `autoninja -C out/Android chrome_public_apk`.

`build/args-dev.gn` is a faster non-official config for development. After building, open
`test/iris-selftest.html` from a local server to check the removed APIs, permissions, ad blocking and headers.

## Repository layout

| Path | Contents |
|---|---|
| `patches/` | one script per change; `apply-all.sh` runs them in order |
| `build/` | gn args for Linux, Android and dev builds |
| `adblock/` | ruleset builder; bundled lists and their license |
| `packaging/` | .deb notes, snap, launcher, release verification tools |
| `branding/` | icons, orb logo, theme palettes |
| `website/` | the project website (`index.html`); `build-readme.py` turns it into this README, `make-banner.py` draws the banner |
| `test/` | self-test page for a built browser |
| `FEATURES.md` | every feature and the patch behind it |

## Reporting problems

Bugs: [GitHub issues](https://github.com/jegly/iris/issues). Security issues: please report privately through
GitHub's *Report a vulnerability* (Security tab) rather than a public issue.

## Credits and licenses

- Chromium: BSD-3-Clause and the licenses of its third-party components (see `chrome://credits` in the browser).
- EasyList and EasyPrivacy filter lists: The EasyList authors, GPLv3+ / CC BY-SA 3.0
  (shipped as `/usr/share/doc/iris-browser-stable/filter-lists-LICENSE`).
- DotGothic16 font (Iris wordmark): The DotGothic16 Project Authors, SIL Open Font License 1.1 (`website/fonts/OFL.txt`).
- Catppuccin colour palette: the Catppuccin project, MIT.
- Iris patches and tooling: GPL-2.0-or-later (`LICENSE`). "Or later" because Chromium contains Apache-2.0
  components, which are compatible with GPL-3.0 but not GPL-2.0-only.

Iris is made by [jegly](https://github.com/jegly). It is based on Chromium and not affiliated with Google.
