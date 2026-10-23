#!/usr/bin/env python3
# Iris — prove every patch in apply-all.sh is really in the Chromium tree (jegly 2026-10-23, after a false SKIP:
# apply-iris-runner.sh's "already applied" marker also matched a line apply-web-recolor.sh adds, so RUNNER's WebGL
# exemption never landed in 0.0.0.9). Read-only: nothing in the tree is written.
#   1. Python edit(p, old, new, marker, label) patches: for every SKIP, each line `new` adds must be in the file.
#      A missing line that a later patch rewrites (it appears in another patch's source, or twice in its own) is
#      reported as "rewritten" and does not fail the check.
#   2. Shell flip / flip_anchor / flip_slurp calls: the new value must be present and the old one gone.
#   3. Every file in patches/src must be byte-identical to its copy in the tree.
# Usage: patches/check-applied.py [-v] [chromium-src]   (exit 1 when something is missing; run by apply-all.sh)
import os, re, subprocess, sys

ARGS = [a for a in sys.argv[1:] if a != "-v"]
SRC = os.path.abspath(os.path.expanduser(ARGS[0] if ARGS else "~/Documents/chromium/src"))
PATCHES = os.path.dirname(os.path.abspath(__file__))
order = re.findall(r"^\s+(apply-[\w-]+)", open(os.path.join(PATCHES, "apply-all.sh")).read(), re.M)
texts = {n: open(os.path.join(PATCHES, n + ".sh")).read() for n in order
         if os.path.exists(os.path.join(PATCHES, n + ".sh"))}
fail, rewritten = [], []

# Hand-verified 2026-10-23 against the 156.0.8078.47 tree: a later patch rewords or extends these lines; the change
# itself is in the tree. Key: (patch, start of the line it adds). Add an entry only after checking the tree by hand.
VERIFIED = {
    ("apply-extension-update-toggle", 'label="Update extensions'): "strings moved to $i18n by -strings.sh",
    ("apply-extension-update-toggle", 'sub-label="Checks the Chrome'): "strings moved to $i18n by -strings.sh",
    ("apply-ua-navigator-consistency", 'if (iris_user_agent.contains("Safari/")'): "iPhone case added around it",
    ("apply-ua-navigator-consistency", '!iris_user_agent.contains("Chrome/")'): "same block, re-indented",
    ("apply-privacy-toggles-1", '"No 3D graphics on any website'): "summary reworded by a later patch",
    ("apply-iris-hardening-page", '{"Ads and trackers"'): "group extended by later switches",
    ("apply-iris-hardening-page", '{"Data", "iris_shredding"'): "group extended by later switches",
    ("apply-tracking-param-toggle", '{"Ads and trackers"'): "group extended by later switches",
    ("apply-block-downloads", '"iris_clear_clipboard", "iris_download_ask"'): "clickfix switch inserted",
    ("apply-toolbar-buttons", 'sub-label="Locks and closes Iris.'): "reworded by the same patch (lock mode)",
    ("apply-android-screenshot-protection", "getPreferenceScreen("): "call reformatted",
    ("apply-page-info-identity", '{"'): "preset table gained a third field (13 identities)",
    ("apply-page-info-identity", "menu_model_.AddRadioItemWithStringId"): "menu rebuilt for 13 identities",
    ("apply-page-info-identity", "SetSubtitleText("): "menu rebuilt for 13 identities",
    ("apply-android-per-site", '"Iris (default)", "Firefox on Linux"'): "list extended to 13 identities",
    ("apply-android-per-site", 'new String[] {"", "firefox_linux"'): "list extended to 13 identities",
    ("apply-glass-window", "// Iris: see-through glass window"): "frame code replaced by the newer glass version",
    ("apply-glass-window", "// bar as translucent"): "frame code replaced by the newer glass version",
    ("apply-glass-window", "// bar flickers."): "frame code replaced by the newer glass version",
    ("apply-glass-window", "return height + 40;"): "frame code replaced by the newer glass version",
    ("apply-extension-update-toggle", "<!-- Iris: extension update toggle"): "comment reworded by -strings.sh",
    ("apply-iris-permissions", "IrisWebGLAllowed(web_contents, web_contents->GetLastCommittedURL());"):
        "wrapped by apply-iris-runner.sh (error page exemption)",
}

def rewritten_elsewhere(name, line):
    line = line.strip()
    return any(n == name and line.startswith(pre) for n, pre in VERIFIED)

# --- 1. Python edit() patches ------------------------------------------------------------------------------------
SKIP = re.compile(r'if marker in s: print\("SKIP already applied: %s \(%s\)" % \(p, label\)\); return')
REPORT = ('if marker in s:\n'
          '        for _l in {var}.splitlines():\n'
          '            if _l.strip() and _l not in {old} and _l.strip() not in s:\n'
          '                print("IRIS_MISSING\\t%s\\t%s\\t%s" % (p, label, _l.strip()))\n'
          '        return')
for name, t in texts.items():
    cwd = SRC + "/chrome/installer/linux" if 'cd "$SRC/chrome/installer/linux"' in t else SRC
    for m in re.finditer(r"<<'PY'\n(.*?)\nPY\n", t, re.S):
        code = m.group(1)
        if not SKIP.search(code):
            continue
        parts = re.split(r"(?=^def )", code, flags=re.M)
        out = []
        for part in parts:
            sig = re.match(r"def \w+\(([^)]*)\)", part)
            args = [a.strip() for a in sig.group(1).split(",")] if sig else []
            if "new" in args and "old" in args:
                part = SKIP.sub(REPORT.format(var="new", old="old.splitlines()"), part)
            elif "block" in args:
                part = SKIP.sub(REPORT.format(var="block", old="[]"), part)
            elif "pairs" in args:
                part = SKIP.sub(REPORT.format(var="chr(10).join(n for o, n in pairs)",
                                              old="chr(10).join(o for o, n in pairs).splitlines()"), part)
            out.append(part)
        code = "".join(out)
        code = re.sub(r'open\(([^()]*?),\s*"w"\)\.write\(', r"(lambda *a: None)(", code)  # never write
        if not os.path.isdir(cwd):
            fail.append("%s: directory missing: %s" % (name, cwd)); continue
        r = subprocess.run([sys.executable, "-c", code], cwd=cwd, capture_output=True, text=True,
                           env=dict(os.environ, IRIS_PATCH_DIR=PATCHES))
        for line in r.stdout.splitlines():
            if line.startswith("IRIS_MISSING\t"):
                _, p, label, miss = line.split("\t", 3)
                (rewritten if rewritten_elsewhere(name, miss) else fail).append("%s: %s (%s): %s" % (name, p, label, miss[:100]))
            elif line.startswith("OK "):
                fail.append("%s: would still apply: %s" % (name, line[5:105]))
        if r.returncode != 0:
            fail.append("%s: check could not run: %s" % (name, (r.stderr.strip().splitlines() or ["?"])[-1][:120]))

# --- 2. Shell flip calls -------------------------------------------------------------------------------------------
def shell_words(s):
    """Split shell words: '...' and "..." quotes (may span lines), backslash-newline outside quotes = space."""
    words, cur, i, q, have = [], [], 0, None, False
    while i < len(s):
        c = s[i]
        if q:
            if c == q: q = None
            elif q == '"' and c == "\\" and i + 1 < len(s) and s[i + 1] in '"\\$`': i += 1; cur.append(s[i])
            else: cur.append(c)
        elif c in "'\"": q = c; have = True
        elif c == "\\" and i + 1 < len(s) and s[i + 1] == "\n": i += 1
        elif c in " \t":
            if have: words.append("".join(cur)); cur, have = [], False
        elif c == "\n": break
        else: cur.append(c); have = True
        i += 1
    if have: words.append("".join(cur))
    return words

for name, t in texts.items():
    if not re.search(r"^(flip|flip_anchor|flip_slurp)\(\)", t, re.M):
        continue
    body = re.sub(r"^\s*\w+\(\)\s*\{.*?^\}", "", t, flags=re.S | re.M)
    env = {"SRC": SRC}
    for m in re.finditer(r"^([A-Z_]+)=(.+)$", body, re.M):
        v = shell_words(m.group(2))
        env[m.group(1)] = v[0] if v else ""
    for k in list(env):  # resolve ${X:-default} and $X inside values
        env[k] = re.sub(r"\$\{(\w+):-([^}]*)\}", lambda v: os.environ.get(v.group(1), v.group(2)), env[k])
        env[k] = re.sub(r"\$\{?(\w+)\}?", lambda v: env.get(v.group(1), v.group(0)), env[k])
    for m in re.finditer(r"^\s*(flip|flip_anchor|flip_slurp)\s+", body, re.M):
        w = shell_words(body[m.end():])
        w = [re.sub(r"\$\{?(\w+)\}?", lambda v: env.get(v.group(1), v.group(0)), x) for x in w]
        f = os.path.join(SRC, w[0])
        if not os.path.exists(f):
            fail.append("%s: %s: file missing" % (name, w[0])); continue
        s = open(f, errors="replace").read()
        if m.group(1) == "flip":
            old, new = w[1], w[2]
            if new not in s: fail.append("%s: %s: not applied: %s" % (name, w[0], new[:90]))
            elif old not in new and old in s: fail.append("%s: %s: old text still there: %s" % (name, w[0], old[:90]))
        elif m.group(1) == "flip_anchor":
            a, fr, to = w[1], w[2], w[3]
            if not re.search(re.escape(a) + r"\s*" + re.escape(to), s):
                fail.append("%s: %s: not applied: %s -> %s" % (name, w[0], a.splitlines()[0][:60], to))
            if re.search(re.escape(a) + r"\s*" + re.escape(fr), s):
                fail.append("%s: %s: old value still there: %s" % (name, w[0], a.splitlines()[0][:60]))
        else:  # flip_slurp: marker is the replacement itself
            if w[3] not in s: fail.append("%s: %s: not applied: %s" % (name, w[0], w[3][:90]))

# --- 3. patches/src copies -----------------------------------------------------------------------------------------
n_src = 0
for root, _, files in os.walk(os.path.join(PATCHES, "src")):
    for fn in files:
        a = os.path.join(root, fn); rel = os.path.relpath(a, os.path.join(PATCHES, "src")); n_src += 1
        b = os.path.join(SRC, rel)
        if not os.path.exists(b) or open(a, "rb").read() != open(b, "rb").read():
            fail.append("patches/src: %s differs from the tree" % rel)

if "-v" in sys.argv:
    for r in rewritten: print("rewritten by a later patch (OK): " + r)
for f in fail: print("MISSING: " + f)
print("%d patches, %d patches/src files checked (%d hand-verified rewordings, -v lists them): %s" % (len(texts), n_src, len(rewritten),
      "ALL APPLIED" if not fail else "%d PROBLEM(S)" % len(fail)))
sys.exit(1 if fail else 0)
