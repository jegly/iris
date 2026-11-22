#!/usr/bin/env bash
# Iris — no shared cache for "pervasive" third-party files (jegly 2026-11-20: "Yes, turn it off").
# Chromium (since ~146, chromestatus 5202380930678784) keeps a hand-picked list of a few hundred very common third-party
# scripts/styles/dictionaries (analytics, video embeds, captchas, social widgets, ad libraries; the URL patterns are
# compiled in: services/network/pervasive_resources/shared_resource_checker_patterns.h) in ONE single-keyed HTTP
# cache shared by every site, an exception to per-site cache partitioning. 158 also turned on
# kPervasiveSharedDictionaries (compression dictionaries in an unpartitioned, single-keyed store).
# Iris turns both off, so every file is cached per site again (a site can't probe the shared cache for traces of
# other sites). Gates (158): SharedResourceChecker::enabled_ = kCacheSharingForPervasiveResources;
# SharedDictionaryManager::GetPervasiveStorage() needs BOTH features. Field trials can't re-enable them in Iris.
# Cost: those files are downloaded again per site (many are blocked by the ad blocker anyway).
# STATUS 2026-11-20: copy-tested on 158.0.8127.43, NOT compile-proven yet (services/network/public/cpp features.o).
# Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
p = "services/network/public/cpp/features.cc"
edit(p,
     "BASE_FEATURE(kCacheSharingForPervasiveResources,\n"
     "             base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "BASE_FEATURE(kCacheSharingForPervasiveResources,\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no shared cache (apply-pervasive-cache-off.sh)\n",
     "kCacheSharingForPervasiveResources,\n             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris",
     "pervasive resource cache sharing off")
edit(p,
     "BASE_FEATURE(kPervasiveSharedDictionaries, base::FEATURE_ENABLED_BY_DEFAULT);\n",
     "BASE_FEATURE(kPervasiveSharedDictionaries,\n"
     "             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris: no shared dictionaries (apply-pervasive-cache-off.sh)\n",
     "kPervasiveSharedDictionaries,\n             base::FEATURE_DISABLED_BY_DEFAULT);  // Iris",
     "pervasive shared dictionaries off")
# Guard: nothing else may read these patterns without the feature check (158: SharedResourceChecker only).
c = open("services/network/pervasive_resources/shared_resource_checker.cc").read()
if "enabled_ = base::FeatureList::IsEnabled(\n      features::kCacheSharingForPervasiveResources);" not in c:
    die("SharedResourceChecker no longer gates on kCacheSharingForPervasiveResources (drift: re-check the gate)")
print("GUARD ok: SharedResourceChecker gated on kCacheSharingForPervasiveResources")
PY
echo "=== pervasive cache sharing off complete ==="
