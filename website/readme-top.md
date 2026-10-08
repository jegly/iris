## Security Philosophy

> **Iris is built to be substantially more hardened against browser-side exploitation than mainstream browsers, because it removes entire classes of web capabilities and attack surface rather than merely mitigating their abuse.**

Most browsers approach security by attempting to safely support an enormous and constantly expanding web platform. Powerful APIs are enabled by default, complex subsystems remain available for compatibility, and security largely depends on sandboxing, permission prompts, exploit mitigations, and continuous patching.

Iris takes a fundamentally different approach:

### Reduce the attack surface first.

If a capability is unnecessary for ordinary browsing, Iris can **remove or disable it entirely** rather than relying on a security boundary to contain it after compromise.

Removed or switched off, the high-complexity and high-risk web functionality:

- **JIT compilation disabled** (can be allowed per site)
- **WebAssembly disabled** (can be allowed per site)
- **WebRTC disabled**
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
- **Aggressive permission restrictions**: camera, microphone, location and more stay blocked until you allow a site
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
| **Built-in tracker blocking** | 🟢 | 🟡 |
| **Third-party cookies blocked** | 🟢 | 🟡 |
| **Fingerprinting protection** | 🟢 | 🟡 |
| **Canvas fingerprint randomization** | 🟢 | 🟡 |
| **Audio fingerprint protection** | 🟢 | 🟡 |
| **Hardware fingerprint reduction** | 🟢 | 🟡 |
| **Bounce-tracking protection** | 🟢 | 🟡 |
| **Tracking-parameter stripping** | 🟢 | 🟡 |
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
| **Camera/mic blocked until permission** | 🟢 | 🟢 |
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
