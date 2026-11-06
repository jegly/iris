# Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
# Iris (apply-android-gms-stubs.sh): parse javap dumps of the Google header jars; compute the API closure Chromium needs. See README.md here.
# Parse javap -public -constants dumps into {class: {"decl":..., "members":[...]}}; compute the type closure.
import re, sys, glob, json, os
G = re.compile(r'\b(com\.google\.(?:android\.gms|firebase|android\.play|mlkit|android\.datatransport)\.[A-Za-z0-9_.$]+)')
classes = {}
cur = None
for f in glob.glob(os.path.expanduser("~/.buildtmp/item9/javap/*.txt")):
    for line in open(f):
        line = line.rstrip("\n")
        if not line or line.startswith("Compiled from") or line.startswith("Warning"): continue
        m = re.match(r'^(public|protected)?\s*([a-z ]*?)(class|interface|enum|@interface) (\S+)(.*)\{$', line.strip()) if not line.startswith("  ") else None
        if m:
            cur = m.group(4).split("<")[0]
            classes[cur] = {"decl": line.strip(), "members": []}
            continue
        if line.strip() == "}": cur = None; continue
        if cur: classes[cur]["members"].append(line.strip())
roots = [l.strip() for l in open(os.path.expanduser("~/.buildtmp/item9/classes.txt")) if l.strip()]
roots += """com.google.mlkit.common.MlKit com.google.mlkit.genai.common.DownloadCallback com.google.mlkit.genai.common.FeatureStatus
com.google.mlkit.genai.common.GenAiException com.google.mlkit.genai.common.StreamingCallback com.google.mlkit.genai.prompt.CountTokensResponse
com.google.mlkit.genai.prompt.GenerateContentRequest com.google.mlkit.genai.prompt.GenerateContentResponse com.google.mlkit.genai.prompt.Generation
com.google.mlkit.genai.prompt.GenerationConfig com.google.mlkit.genai.prompt.GenerativeModel com.google.mlkit.genai.prompt.java.GenerativeModelFutures
com.google.mlkit.genai.prompt.TextPart""".split()
# imports use '.' for nested classes: map to binary names
def resolve(n):
    if n in classes: return n
    parts = n.split(".")
    for i in range(len(parts)-1, 0, -1):
        b = ".".join(parts[:i]) + "$" + "$".join(parts[i:])
        if b in classes: return b
    return None
missing = [r for r in roots if not resolve(r)]
S = set(); todo = [resolve(r) for r in roots if resolve(r)]
while todo:
    c = todo.pop()
    if c in S: continue
    S.add(c)
    # outer classes of nested ones
    if "$" in c: todo.append(c.rsplit("$",1)[0])
    # every nested type of a class in use (Chromium names X.Builder etc. without importing them)
    todo += [k for k in classes if k.startswith(c + "$") and "$" not in k[len(c) + 1:] and not k[len(c) + 1:][:1].isdigit()]
    text = classes[c]["decl"] + "\n" + "\n".join(classes[c]["members"])
    for t in G.findall(text):
        t = t.rstrip(".")
        r = resolve(t) or (t if t in classes else None)
        if r and r not in S: todo.append(r)
print("roots", len(roots), "missing", missing)
print("closure", len(S))
from collections import Counter
print(Counter(".".join(c.split(".")[:5]) for c in S).most_common(25))
json.dump({"classes": classes, "closure": sorted(S), "roots": roots}, open(os.path.expanduser("~/.buildtmp/item9/gen/model.json"), "w"))
