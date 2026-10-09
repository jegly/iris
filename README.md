<p align="center"><img src="website/iris-banner.svg" alt="Iris: a hardened, privacy-first browser built on Chromium" width="81%"></p>

Iris is a security-hardened, privacy-focused browser engineered to reduce attack surface, enforce isolation boundaries, and defend against an increasingly scalable threat landscape.

Named after the Greek goddess who carried messages between gods and mortals, Iris represents the boundary through which information flows. In modern computing, the browser occupies precisely this role: processing untrusted content, executing remote code, and mediating access to sensitive information across an extensive attack surface.

Iris draws on the security architectures of established hardened browsers, building on proven defensive techniques while pursuing a more robust security model. Its design prioritizes attack surface minimization, site isolation, memory safety, and post-quantum cryptography.

As AI accelerates vulnerability discovery and lowers the barriers to developing sophisticated attacks, browser security demands defense in depth. Iris addresses this challenge through layered protections designed to reduce exploitability, contain compromises, and strengthen the confidentiality and integrity of user data.

**Open source. Security by architecture. Privacy by design.**

## Security Philosophy

> **Iris is built to be substantially more hardened against browser-side exploitation than mainstream browsers, because it removes entire classes of web capabilities and attack surface rather than merely mitigating their abuse.**

Most browsers approach security by attempting to safely support an enormous and constantly expanding web platform. Powerful APIs are enabled by default, complex subsystems remain available for compatibility, and security largely depends on sandboxing, permission prompts, exploit mitigations, and continuous patching.

Iris takes a fundamentally different approach:

### Reduce the attack surface first.

If a capability is unnecessary for ordinary browsing, Iris can **remove or disable it entirely** rather than relying on a security boundary to contain it after compromise.

Removed or switched off, the high-complexity and high-risk web functionality:

- **JIT compilation disabled** (can be allowed per site)
- **WebAssembly disabled** (can be allowed per site)
- **WebRTC disabled**, and with it camera and microphone access for websites
- **Geolocation, MediaRecorder, WebCodecs and WebTransport removed**
- **WebGPU disabled**
- **WebXR and WebNN disabled**
- **WebUSB, WebHID, Web Serial and Bluetooth APIs disabled**
- **NFC and other hardware interfaces disabled**
- **File System Access pickers disabled**
- **Screen capture and screen sharing disabled**
- **Background networking and unnecessary remote services removed**
- **Google services, sync and telemetry removed**

Hardened, so what is left is harder to exploit:

- **Strict site and origin isolation**
- **Hardened renderer and process configuration** (JIT-less renderers, a sandboxed network service)
- **Control-flow and memory-corruption mitigations**
- **Aggressive permission restrictions**: notifications, clipboard and more stay blocked until you allow a site
- **TLS 1.3 minimum and hardened cryptographic defaults**

Added, to protect your privacy and your data:

- **Encrypted Client Hello (ECH)** and **post-quantum key exchange**, with an optional strict post-quantum mode
- **Built-in tracker and advertising protection**
- **Fingerprinting reduction and randomization**
- **Automatic data cleanup and shredding** (off until you switch it on)
- **Application-level locking and protected local data**

### Mitigation vs. elimination

A conventional browser might approach a dangerous capability like this:

```
Powerful Web API
       ↓
    Sandbox
       ↓
 Permission Model
       ↓
 Exploit Mitigations
       ↓
    Patch Bugs
```

Iris asks a different question:

```
Do we need this capability at all?
       │
      NO
       ↓
Remove it.
```

This distinction matters.

A vulnerability in an enabled subsystem can potentially become an exploitable browser compromise. Removing the subsystem eliminates that entire category of vulnerabilities from the browser's reachable attack surface.

Iris therefore does not attempt to make **every part of the modern web platform safe**.

It deliberately makes **less of the web platform available to hostile websites in the first place**.

### Security through reduction

The goal is not to claim that Iris makes exploitation impossible. No sufficiently complex software can make that guarantee.

The goal is to make successful exploitation **harder, narrower, and less useful** by reducing:

1. **The amount of code exposed to untrusted web content**
2. **The number of privileged browser interfaces**
3. **The number of hardware and operating-system interfaces reachable from web content**
4. **The number of complex subsystems that can be targeted**
5. **The information available for fingerprinting**
6. **The capabilities available after a site is compromised**
7. **The amount of unnecessary network communication**
8. **The amount of persistent local browser state**

This is **defense in depth through attack-surface reduction**.

### Iris vs. other browsers

Mainstream browsers are designed to support an extraordinarily broad range of modern web applications. That is a legitimate and valuable design goal. Iris deliberately makes a different trade-off.

The chart compares Iris with other browsers in general, as a feature list, not a score. Read each row as a question, for example "Is JIT disabled?"

> **Legend:** 🟢 Yes, built in &nbsp; 🟡 Partly, optional, or differs between browsers &nbsp; 🔴 No

The last six rows are things Iris deliberately leaves out, so a 🔴 there is a choice, not a gap. See "What you give up" below.

| Security / privacy feature | **Iris** | Other browsers |
| --- | --- | --- |
| **JIT JavaScript disabled** | 🟢 | 🔴 |
| **WebAssembly disabled** | 🟢 | 🔴 |
| **WebRTC disabled** | 🟢 | 🔴 |
| **Camera / microphone API removed** | 🟢 | 🔴 |
| **Geolocation API removed** | 🟢 | 🔴 |
| **WebCodecs / WebTransport removed** | 🟢 | 🔴 |
| **WebGPU disabled by default** | 🟢 | 🔴 |
| **WebXR / WebNN disabled** | 🟢 | 🔴 |
| **USB / HID / Serial / Bluetooth / NFC APIs removed** | 🟢 | 🔴 |
| **File System Access disabled** | 🟢 | 🔴 |
| **Screen sharing disabled** | 🟢 | 🔴 |
| **Strict site isolation** | 🟢 | 🟢 |
| **Strict origin isolation** | 🟢 | 🟡 |
| **JIT-less renderer sandbox** | 🟢 | 🔴 |
| **CFI / compiler hardening** | 🟢 | 🟢 |
| **Memory-safe image decoders** | 🟢 | 🟡 |
| **Built-in ad blocking** | 🟢 | 🟡 |
| **Per-page blocked count and site panel** | 🟢 | 🟡 |
| **Built-in tracker blocking** | 🟢 | 🟡 |
| **Third-party cookies blocked** | 🟢 | 🟡 |
| **Fingerprinting protection** | 🟢 | 🟡 |
| **Canvas fingerprint randomization** | 🟢 | 🟡 |
| **Audio fingerprint protection** | 🟢 | 🟡 |
| **Hardware fingerprint reduction** | 🟢 | 🟡 |
| **Bounce-tracking protection** | 🟢 | 🟡 |
| **Tracking-parameter stripping** | 🟢 | 🟡 |
| **Block all third-party requests (option)** | 🟢 | 🟡 |
| **Global Privacy Control** | 🟢 | 🟡 |
| **Google telemetry removed** | 🟢 | 🟡 |
| **Google sign-in / sync removed** | 🟢 | 🟡 |
| **Background networking minimized** | 🟢 | 🟡 |
| **Encrypted DNS** | 🟢 | 🟢 |
| **HTTPS-Only mode** | 🟢 | 🟡 |
| **TLS 1.3 minimum** | 🟢 | 🟡 |
| **Encrypted Client Hello (ECH)** | 🟢 | 🟢 |
| **Post-quantum TLS** | 🟢 | 🟢 |
| **Strict PQ-only mode** | 🟢 | 🔴 |
| **App lock / passphrase** | 🟢 | 🔴 |
| **Automatic data shredding** | 🟢 | 🟡 |
| **Per-site JavaScript control** | 🟢 | 🟡 |
| **Per-site browser identity** | 🟢 | 🔴 |
| **Unused permissions automatically revoked** | 🟢 | 🟡 |
| **Tor routing built in** | 🔴 | 🔴 |
| **Anonymous network identity** | 🔴 | 🟡 |
| **DRM / Widevine** | 🔴 | 🟢 |
| **Browser video calls** | 🔴 | 🟢 |
| **Enterprise / MDM support** | 🔴 | 🟢 |
| **Maximum web compatibility** | 🔴 | 🟢 |

"Other browsers" shows the value most mainstream and privacy-focused browsers share; where they differ it shows 🟡. Browsers change quickly, so check the one you use.

Iris is therefore **not simply another privacy browser**. It is a security-oriented Chromium fork built around a more fundamental premise:

> **The safest browser capability is often the capability that a hostile website cannot access because the browser does not provide it.**

### A deliberate trade-off

This approach inevitably breaks parts of the modern web.

Video conferencing, DRM, certain hardware-enabled applications, WebGPU applications, advanced web apps, browser payments, screen sharing and other functionality may not work in Iris.

This is intentional.

Iris prioritizes:

**security and privacy > compatibility**

rather than:

**compatibility > security and privacy**

Users who need every modern web capability should use a mainstream browser.

Users who are willing to sacrifice functionality in exchange for a **much smaller browser attack surface** are the target audience for Iris.

### The core principle

> **Don't just sandbox the attack surface. Shrink it.**

Iris is built around the belief that browser security should not depend exclusively on making an enormous web platform perfectly secure.

**Less code. Less capability. Less exposure. Fewer ways in.**

## Download

| Platform | Package | Install | Notes |
|---|---|---|---|
| **Ubuntu / Debian** | [.deb · amd64](https://github.com/jegly/iris/releases/latest) | `sudo apt install ./iris-browser-stable_*_amd64.deb` | Includes the setuid sandbox helper and an AppArmor profile, so the full Chromium sandbox works without extra setup. |
| **Android** | [.apk · arm64](https://github.com/jegly/iris/releases/latest) | `adb install iris-*.apk` | Package `io.jegly.iris`. Allow installs from your browser or file manager when Android asks. Runs without Google Play Services. |
| **Snap** | [snap · amd64](https://github.com/jegly/iris/releases/latest) | `sudo snap install --dangerous iris-browser_*.snap` | Built from the same .deb, with the full browser sandbox. Until it's in the Snap Store, install the file from the release, then run `sudo snap connect iris-browser:browser-sandbox` and `sudo snap connect iris-browser:u2f-devices` once. |

## What Iris technically changes

Iris starts from upstream Chromium source and applies small, documented patches plus a hardened build configuration. Red lines are removed or switched off; green lines are added or switched on by default. Everything applies to both Ubuntu and Android unless a line is tagged with one of them.

### Tracking & ads

```diff
+ Ad and tracker blocking on every site (EasyList + EasyPrivacy built in, with a per-site switch)
+ Extra filter lists for more ad and tracker blocking, one switch
+ Block third-party requests: a switch that stops pages loading anything from other sites (off by default; breaks many sites)
- Topics, Protected Audience and Shared Storage (Privacy Sandbox ad APIs)
- Third-party cookies
- <a ping>, sendBeacon() and fetchLater() (click and exit pings)
- Network Error Logging and the Reporting API (sites can't make your browser report back to them)
- HSTS on subresources (used as a supercookie)
- window.name carried from one site to the next
- Prefetch, prerender and preconnect of pages you haven't opened
- Text-fragment links, signed exchanges and compression dictionaries
- FedCM sign-in prompts
- Tracking parameters such as utm_, fbclid and gclid in links
+ Data stored by bounce-tracking sites deleted automatically (Chromium default, kept)
+ Global Privacy Control (Sec-GPC) sent to every site
+ Heavy ads unloaded automatically (Chromium default, kept)
```

### Fingerprinting

```diff
- navigator.userAgentData and every Sec-CH-UA header (sites can't request them either)
- Servers asking for extra device details during the connection handshake
- Battery status, gamepads, speech voices and speech recognition
- Keyboard layout, multi-screen details and navigator.connection
- Local font access, the eyedropper and the installed-apps list
- Origin trials (sites can't switch removed features back on)
+ A single Accept-Language value instead of your full list
+ Canvas and audio fingerprints randomised per site and per session, or blanked, per site
+ CPU core count and device memory reported as common fixed values
- WebGL until you allow a site (off by default, one click to enable)
```

### Google services

```diff
- Google sign-in and sync, cross-device sign-in and shared tab groups
- Search suggestions sent as you type, and mistyped addresses sent to Google for suggestions
- Translate offers, spellcheck dictionary downloads and autofill server lookups
- Built-in AI: Prompt, Summarizer, Writer, Rewriter, Translator and language-detection APIs, the on-device model, AI checkout scanning and the AI settings page
- Google Lens, AI Mode and Gemini
- Safe Browsing surveys and file uploads for deep scanning
- Remote new tab page, search-engine logo, popular sites and Google's favicon server
- Cast device discovery, the Discover feed and Touch to Search
- Google sign-in widgets on other sites, until you allow them
- Background networking, field-trial experiments, usage statistics and crash reports
+ DuckDuckGo as the default search engine, and a new tab page that stays local
+ 20 search engines to choose from in every country, privacy-first, all of them reachable over TLS 1.3
```

### Web APIs

```diff
- JavaScript JIT and WebAssembly for websites (can be allowed per site)
- WebRTC, and camera and microphone access for websites (getUserMedia)
- MediaRecorder and captureStream() on canvas and video
- WebCodecs encoders and decoders, and WebTransport
- The Geolocation API and the <geolocation> element
- WebGPU, WebXR and WebNN
- WebUSB, WebHID, Serial, Bluetooth, NFC and Direct Sockets
- File System Access pickers, the old webkitRequestFileSystem API, and wake lock
- Push messaging, background fetch, Web Share, contacts and WebOTP
- Presentation, remote playback, app badging and vibration
- Device posture, compute pressure, storage buckets and digital credentials
- Window-controls overlay, sub-apps, launch queue, managed configuration and protocol handlers
- Handwriting ink, raw media-stream processing and Animation Worklet
- Declarative partial page updates (experimental)
- Cross-site scripts that a page inserts with document.write()
- The Payment Request API and its browser-side interface
- Screen sharing
```

### Your controls

```diff
+ App lock: a passphrase before the browser opens
+ Automatic data shredding you can switch on: cookies, site data and cache cleared on a schedule
+ Extension auto-updates off unless you switch them on
+ The app-lock screen follows your theme
+ A shorter Settings: Safety Hub trimmed, no Translate, no Enhanced protection, a simpler autofill page
+ A shield in the toolbar with the number of ads, trackers, cookies and fingerprinting attempts blocked on the page. Its panel holds every Iris setting for the site: ads, cross-site cookies, JavaScript, WebGL, Google sign-in prompts, canvas and audio reading, browser identity and the connection details [Ubuntu]
+ Toolbar buttons for JavaScript on the current site, a new identity (erases site data, cache and history, closes the other tabs and starts fresh) and locking Iris; each can be hidden [Ubuntu]
+ Forget a site: its cookies and data deleted when you close the browser [Ubuntu]
+ A JavaScript on/off switch, globally and per site
+ Per-site controls for JavaScript, cookies and images
+ A different browser identity for any site, from the shield: 13 to pick from, including Firefox, Chrome, Edge, Safari and Samsung Internet on desktop, Android and iPhone
+ Cookies, saved logins and bookmarks encrypted with your passphrase when the app lock is on, open tabs too on Ubuntu
+ All of Iris's own switches on one "Iris hardening" page in Settings [Ubuntu]
+ Switches to block web fonts, autoplay, all downloads and QUIC, to stop sending the Referer, and to clear copied text after 30 seconds
+ Tracking parameters removed from links, with a switch to keep them
+ Blocked pop-ups can be opened once, without allowing the site
+ A light theme by default (Monokai Pro Light) and Catppuccin Mocha in dark mode, with 114 colour palettes (57 light, 57 dark)
+ Round traffic-light window buttons and an optional see-through glass window [Ubuntu]
```

### Network & TLS

```diff
+ TLS 1.3 minimum, with Encrypted Client Hello and post-quantum key exchange
+ CNSA 2.0 cipher and key-exchange preferences
+ Strict post-quantum mode, off by default: ML-KEM-1024 key exchange and AES-256 only (Settings → Privacy and security → Security; some sites won't load)
+ Merkle Tree Certificate verification, ready for post-quantum certificates
+ Connection details: TLS version, cipher, hash, key exchange, server signature and ECH (in the shield on Ubuntu, in the lock icon on Android)
+ Cookies only sent back to the scheme and port that set them
+ Encrypted DNS in secure mode: Quad9 by default, 21 resolvers to choose from
+ HTTPS-Only mode: a warning before any http:// page
+ Full URLs in the address bar, www. and m. included
+ Websites can't reach your router, printer or localhost (Chromium default, kept)
+ Cache, connections and storage partitioned per site (Chromium default, kept)
+ Cookies and saved logins encrypted with a key from your desktop keyring [Ubuntu]
+ Lookalike-domain (IDN homograph) warnings (Chromium default, kept)
```

### Memory safety & compiler

```diff
+ Control-flow integrity (CFI, including indirect calls) with a ThinLTO release build
+ Strong stack protector, stack-clash protection and zero-initialised stack variables
+ Shadow call stack, plus pointer authentication and branch target checks (PAC/BTI) [Android]
+ Hardened C++ library with bounds checks, and _FORTIFY_SOURCE (level 3 [Ubuntu])
+ Array-bounds traps and defined integer overflow (Chromium default, kept)
+ Full RELRO, non-executable stack and position-independent executables
+ PartitionAlloc hardening in every process; internal safety checks kept on in release
+ Memory-safe Rust decoders for JPEG, JPEG XL, ICO and BMP images
+ Profile-guided optimisation for a faster browser
- Hardware video decode, SwiftShader, remote desktop, VR/AR, Widevine DRM and the on-device AI model, all left out of the build
- Printing and local-network device discovery
- Page previews, media remoting, enterprise file scanning, the Bluetooth and printing system libraries and the AV1 encoder, left out of the build
```

### Process isolation

```diff
+ Strict site isolation on desktop and Android: every site in its own process
+ Origin-keyed processes and strict origin isolation, so subdomains are separated too
+ Error pages and sandboxed iframes in isolated processes
+ V8 heap sandbox; web renderers run JIT-less with a tighter sandbox
+ The network service, which handles everything from the internet, sandboxed too [Ubuntu]
+ Other programs running as you can't read the browser's memory [Ubuntu]
+ Setuid sandbox helper and AppArmor profile in the .deb, so the full sandbox works without user namespaces [Ubuntu]
```

### Defaults & permissions

```diff
+ Notifications, clipboard and more than 30 other site permissions start as Not allowed until you allow a site
+ Web MIDI, idle detection, motion and light sensors and background sync blocked until you allow a site
+ Permission prompts only after a click; unused site permissions revoked automatically
+ Popups only from real clicks; downloads never open by themselves
+ PDFs open in your system viewer instead of inside the browser
+ Media licence requests over HTTPS only, with size limits
- Admin and MDM policies: nothing outside the browser can reconfigure it
- Kerberos and enterprise management features, left out of the build
- Offers to save passwords, addresses and cards (use a dedicated password manager)
+ Saved passwords filled in only after you pick the account
- First-run welcome and import prompts [Ubuntu]
- Remote debugging, and the --load-extension launch flag
- XSLT (an old attack surface)
```

### Android only

```diff
+ No location or nearby-device access
+ Every protection built into the app itself, because Android ignores launch flags
+ Installs alongside Chrome as its own app (io.jegly.iris)
+ App lock with fingerprint, and screenshots blocked
- Trust in user-installed CA certificates (blocks TLS interception)
- Android and Google cloud backups of browser data
- The first-run setup flow and DRM preprovisioning at startup
- Google services pages, Safety check, Developer options, and Settings search
- The home-screen feed, tips card and loading spinner
+ Fewer permissions and open doors: no Gemini trigger or NFC tag handling, and your bookmarks and history aren't shared with other apps
```

## What you give up

Hardening has a cost. These are the ones you are most likely to notice.

- **Video calls, camera and microphone.** WebRTC and camera and microphone access are gone, so video and voice calls, voice messages and QR-code scanners in the browser won't work. Use their desktop or mobile apps.
- **Location.** Websites can't ask for your location. Maps and store finders fall back to a place you type in.
- **Heavy web apps.** Without JIT, WebAssembly and WebGL, some apps (maps, design tools, games, in-browser editors) are slower or need to be allowed per site. Browser video editors that need WebCodecs won't work.
- **Streaming DRM video.** Widevine isn't included, so Netflix, Disney+ and Spotify's web player won't play protected content.
- **Old sites and Wi-Fi sign-in pages.** Sites that only support TLS 1.2 or plain HTTP show a warning or won't connect. Encrypted DNS never falls back to plain DNS, so some hotel and airport Wi-Fi sign-in pages won't load until you switch secure DNS off.
- **Printing.** Printing is switched off, including "Save as PDF". To keep a copy of a page, save it or take a screenshot.
- **Autofill, saved passwords and payment sheets.** Iris doesn't offer to save addresses, cards or passwords, and sites can't open the browser's payment sheet, so checkouts use their normal card form. A dedicated password manager is the better place for logins.
- **Extension updates.** Extensions work, but they don't update themselves unless you switch that on. Update checks go to the Chrome Web Store, which sees which extensions you have.
- **A forgotten app-lock passphrase.** There's no recovery. Your cookies, logins, bookmarks and tabs are lost, and you start over with a new profile.
- **Logins across ports.** Cookies stay with the port that set them, so services on other ports need their own sign-in.
- **Company-managed setups.** Iris ignores admin and MDM policies and has no Kerberos sign-in, so workplaces can't manage it centrally.

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
- Iris patches and tooling: GPL-2.0-or-later (`LICENSE`). "Or later" because Chromium contains Apache-2.0
  components, which are compatible with GPL-3.0 but not GPL-2.0-only.

Iris is made by [jegly](https://github.com/jegly). It is based on Chromium and not affiliated with Google.
