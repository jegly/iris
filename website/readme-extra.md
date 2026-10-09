## Verify your download

Every release comes with `SHA256SUMS`, signed twice (ML-DSA-87 and Ed25519), and my public keys.

```bash
openssl pkeyutl -verify -pubin -inkey jegly-mldsa87.pub.pem -rawin -in SHA256SUMS -sigfile SHA256SUMS.mldsa87.sig
gpg --import jegly.asc && gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

SHA-256 of the 156.0.8078.11-2 files:

```
57391ab646a268b4bc56dfdc70d42ce881cdd843c1199f37b123bcab9bd64d47  iris-browser-stable_156.0.8078.11-2_amd64.deb
39ca4bd54e04bad7ac7400599ea4dafdbebd333f5d70417c0df095c6b462fe17  iris-browser_156.0.8078.11_amd64.snap
abf6a0ca36f3cfbd2bce3fdc88b86b166b1fff1a35a2599b6fb64847c868d283  iris-156.0.8078.11-2-pqc-signed.apk
```

The ML-DSA-87 check needs OpenSSL 3.5 or newer. `packaging/verify/iris-verify.sh <file>` runs all three and makes
sure the keys are mine. My keys are also in `keys/`:

- ML-DSA-87: `sha256sum jegly-mldsa87.pub.pem` = `3c57473c5b1158c5854d97072db1aca4364c75145aef46130f465a7969e5f91f`
- GPG: `6B84 F8EB 46B9 B634 0BF4 A0E1 A5A5 6CEB 0244 5D37`

## Building from source

Iris is a set of small, guarded patch scripts applied to an upstream Chromium checkout, plus build configs.

1. Get Chromium (`depot_tools`, `fetch chromium`) and check out the base commit
   `fcb358d535effda2ded753c907011e6cdeda089e` (Chromium 156.0.8078.11).
2. The ad-block ruleset is included in `adblock/dist/`. `adblock/build-ruleset.sh` rebuilds it from fresh lists.
3. Apply everything: `patches/apply-all.sh ~/path/to/chromium/src`. Each script checks the code it changes and
   stops with an error if upstream has drifted; re-running is safe.
4. Configure and build:
   ```bash
   mkdir -p out/Linux && cp build/args-linux.gn out/Linux/args.gn && gn gen out/Linux
   autoninja -C out/Linux -k 0 chrome chrome/installer/linux:stable_deb
   ```
   Android: the same with `build/args-android.gn` in `out/Android`, then `autoninja -C out/Android chrome_public_apk`.

`build/args-dev.gn` is a faster non-official config for development. To check a build, run `python3 test/serve.py`
and open the self-test page in Iris.

<details>
<summary><strong>Building for macOS, Windows or iOS</strong></summary>

Iris is built and tested on Ubuntu and Android only. The patches are plain Chromium source changes, so most of them should apply on other platforms too, but nobody has built or tested Iris there yet.

**macOS:** install Xcode, then follow Chromium's [Mac build guide](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md) to get the source. Check out the base commit above, run `patches/apply-all.sh`, start from `build/args-dev.gn` (drop the Linux-only lines), and build with `autoninja -C out/Mac chrome`.

**Windows:** install Visual Studio 2022 with the C++ desktop tools and the Windows SDK, then follow Chromium's [Windows build guide](https://chromium.googlesource.com/chromium/src/+/main/docs/windows_build_instructions.md). The patch scripts need bash and Python, so run them from WSL or Git Bash. Build with `autoninja -C out\Win chrome`.

**iOS:** Apple requires every iOS browser to use WebKit, so Chromium on iOS doesn't use Blink, and most of Iris's engine hardening can't apply there. An iOS build would mainly get the interface and network changes.

**Using a coding agent:** you can also point an AI coding agent (such as Claude Code) at this repository and ask it to build Iris for your platform. It can read the patch scripts, see which ones are Linux- or Android-specific, and adapt the build. Expect to review what it changes.

**Contributions welcome.** If you get Iris building on macOS, Windows or another platform, please open an issue or a pull request with what you changed, so others can use it too.

</details>

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
- 48 light colour palettes: the Gogh colour schemes (github.com/Gogh-Co/Gogh) and their authors, MIT or Apache-2.0.
- Tabler Icons (toolbar icons): Paweł Kuna and contributors, MIT (github.com/tabler/tabler-icons).
- Ideas and approaches, reimplemented in Iris's own patches:
  - Vanadium (GrapheneOS): build hardening flags, privacy defaults and Android credential handling.
  - Cromite and Trivalent: built-in ad blocking, secure DNS by default, removed fingerprinting APIs, distrust of
    user-installed certificates and full URLs.
  - Brave: the shield with a per-page blocked count.
  - Tor Browser: the 100 ms timer precision used by "Coarser timers".
- Iris patches and tooling: GPL-2.0-or-later (`LICENSE`). "Or later" because Chromium contains Apache-2.0
  components, which are compatible with GPL-3.0 but not GPL-2.0-only.

Iris is made by [jegly](https://github.com/jegly) & Claude. It is based on Chromium and not affiliated with Google.
