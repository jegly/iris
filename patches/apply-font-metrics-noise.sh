#!/usr/bin/env bash
# Iris — font-metric fingerprinting: per-site noise on text measurements (issue #1 item 7, jegly 2026-11-05).
# Own code (Bromite's fingerprinting-flags-client-rects-and-measuretext.patch is GPL-3.0-only: not used, not read).
# Verified against 157.0.8103.38. What a page reads back, scaled by IrisFingerprint::ProtectMetric() (patches/src/
# third_party/blink/renderer/core/html/canvas/iris_fingerprint.*, copied by apply-fingerprint.sh): a factor within
# +-0.02% from the site's fingerprint seed and the value itself (same value -> same result; different per site and
# per Iris restart). The site's fingerprint setting applies: "real" = unchanged.
#   - canvas measureText(): every TextMetrics field (width, actual/font bounding boxes, em heights, baselines),
#     BaseRenderingContext2D::measureText -> TextMetrics::IrisProtect (window + OffscreenCanvas in workers).
#   - Element.getClientRects() / getBoundingClientRect() (the binding entry points only; Blink's own layout code
#     that calls GetBoundingClientRect() internally gets exact values).
#   - Range.getClientRects() / getBoundingClientRect().
# What it does NOT cover (honest limits): integer sizes (offsetWidth/offsetHeight/scrollWidth, which can't take
# sub-pixel noise without breaking layouts), IntersectionObserver/ResizeObserver entries, TextMetrics
# getSelectionRects/getActualBoundingBox. Noise defeats hashing of exact values; a script that compares the width of
# a test string against a fallback font can still tell whether a font is installed (that needs a font allowlist).
# STATUS 2026-11-05: copy-tested on 157 file copies, NOT compile-proven.
# Needs apply-fingerprint.sh (iris_fingerprint.* in the tree). Guarded; idempotent; fails loudly on drift.
set -euo pipefail
SRC="${1:-$HOME/Documents/chromium/src}"
cd "$SRC"
[ -f third_party/blink/renderer/core/html/canvas/iris_fingerprint.h ] \
  || { echo "ERROR: iris_fingerprint.h missing (run apply-fingerprint.sh first)" >&2; exit 1; }
python3 - <<'PY'
import sys
def die(m): sys.stderr.write("ERROR: " + m + "\n"); sys.exit(1)
def edit(p, old, new, marker, label):
    s = open(p).read()
    if marker in s: print("SKIP already applied: %s (%s)" % (p, label)); return
    if s.count(old) != 1: die("%s: anchor for %s not found exactly once (drift?)" % (p, label))
    open(p, "w").write(s.replace(old, new, 1)); print("OK   %s : %s" % (p, label))
INC = '#include "third_party/blink/renderer/core/html/canvas/iris_fingerprint.h"  // Iris (font metrics)\n'

# 1. TextMetrics::IrisProtect
TH = "third_party/blink/renderer/core/html/canvas/text_metrics.h"
edit(TH, "class DOMRectReadOnly;\n", "class DOMRectReadOnly;\nclass ExecutionContext;  // Iris\n",
     "class ExecutionContext;  // Iris", "forward declaration")
edit(TH, "  double width() const { return width_; }\n",
     "  double width() const { return width_; }\n"
     "  // Iris: per-site noise on every value (apply-font-metrics-noise.sh).\n"
     "  void IrisProtect(ExecutionContext* context);\n",
     "void IrisProtect(ExecutionContext* context);", "IrisProtect declaration")
TC = "third_party/blink/renderer/core/html/canvas/text_metrics.cc"
edit(TC, '#include "third_party/blink/renderer/core/html/canvas/text_metrics.h"\n',
     '#include "third_party/blink/renderer/core/html/canvas/text_metrics.h"\n' + INC,
     INC, "include")
edit(TC, "TextMetrics::TextMetrics() : baselines_(Baselines::Create()) {}\n",
     "TextMetrics::TextMetrics() : baselines_(Baselines::Create()) {}\n\n"
     "// Iris (apply-font-metrics-noise.sh).\n"
     "void TextMetrics::IrisProtect(ExecutionContext* context) {\n"
     "  auto p = [context](double value) {\n"
     "    return IrisFingerprint::ProtectMetric(context, value);\n"
     "  };\n"
     "  width_ = p(width_);\n"
     "  actual_bounding_box_left_ = p(actual_bounding_box_left_);\n"
     "  actual_bounding_box_right_ = p(actual_bounding_box_right_);\n"
     "  font_bounding_box_ascent_ = p(font_bounding_box_ascent_);\n"
     "  font_bounding_box_descent_ = p(font_bounding_box_descent_);\n"
     "  actual_bounding_box_ascent_ = p(actual_bounding_box_ascent_);\n"
     "  actual_bounding_box_descent_ = p(actual_bounding_box_descent_);\n"
     "  em_height_ascent_ = p(em_height_ascent_);\n"
     "  em_height_descent_ = p(em_height_descent_);\n"
     "  if (baselines_->hasAlphabetic()) {\n"
     "    baselines_->setAlphabetic(p(baselines_->alphabetic()));\n"
     "  }\n"
     "  if (baselines_->hasHanging()) {\n"
     "    baselines_->setHanging(p(baselines_->hanging()));\n"
     "  }\n"
     "  if (baselines_->hasIdeographic()) {\n"
     "    baselines_->setIdeographic(p(baselines_->ideographic()));\n"
     "  }\n"
     "}\n",
     "void TextMetrics::IrisProtect(", "IrisProtect")

# 2. measureText
edit("third_party/blink/renderer/modules/canvas/canvas2d/base_rendering_context_2d.cc",
     "  return MakeGarbageCollected<TextMetrics>(\n"
     "      font, direction, state.GetTextBaseline(), state.GetTextAlign(), text,\n"
     "      host->GetPlainTextPainter());\n",
     "  TextMetrics* iris_metrics = MakeGarbageCollected<TextMetrics>(\n"
     "      font, direction, state.GetTextBaseline(), state.GetTextAlign(), text,\n"
     "      host->GetPlainTextPainter());\n"
     "  iris_metrics->IrisProtect(GetTopExecutionContext());  // Iris (font metrics)\n"
     "  return iris_metrics;\n",
     "iris_metrics->IrisProtect(", "measureText")

# 3. Element.getClientRects / getBoundingClientRect (binding entry points)
E = "third_party/blink/renderer/core/dom/element.cc"
edit(E, '#include "third_party/blink/renderer/core/dom/element.h"\n',
     '#include "third_party/blink/renderer/core/dom/element.h"\n' + INC, INC, "include")
edit(E, "  for (auto& rect : rects) {\n"
        "    GetDocument().AdjustRectForScrollAndAbsoluteZoom(rect,\n"
        "                                                     *element_layout_object);\n"
        "  }\n"
        "  return MakeGarbageCollected<DOMRectList>(rects);\n",
     "  for (auto& rect : rects) {\n"
     "    GetDocument().AdjustRectForScrollAndAbsoluteZoom(rect,\n"
     "                                                     *element_layout_object);\n"
     "    // Iris (font metrics).\n"
     "    rect = IrisFingerprint::ProtectRect(GetExecutionContext(), rect);\n"
     "  }\n"
     "  return MakeGarbageCollected<DOMRectList>(rects);\n",
     "rect = IrisFingerprint::ProtectRect(GetExecutionContext(), rect);", "getClientRects")
edit(E, "  SyncScrollAttemptHeuristic::DidAccessScrollOffset();\n"
        "  return GetBoundingClientRect();\n}\n",
     "  SyncScrollAttemptHeuristic::DidAccessScrollOffset();\n"
     "  // Iris (font metrics): noise for pages only, not for Blink's own callers.\n"
     "  GetDocument().UpdateStyleAndLayoutForNode(this,\n"
     "                                            DocumentUpdateReason::kJavaScript);\n"
     "  return DOMRect::FromRectF(IrisFingerprint::ProtectRect(\n"
     "      GetExecutionContext(), GetBoundingClientRectNoLifecycleUpdate()));\n}\n",
     "GetExecutionContext(), GetBoundingClientRectNoLifecycleUpdate()));", "getBoundingClientRect")

# 4. Range.getClientRects / getBoundingClientRect
R = "third_party/blink/renderer/core/dom/range.cc"
edit(R, '#include "third_party/blink/renderer/core/dom/range.h"\n',
     '#include "third_party/blink/renderer/core/dom/range.h"\n' + INC, INC, "include")
edit(R, "  Vector<gfx::QuadF> quads;\n"
        "  GetBorderAndTextQuads(quads);\n\n"
        "  return MakeGarbageCollected<DOMRectList>(quads);\n",
     "  Vector<gfx::QuadF> quads;\n"
     "  GetBorderAndTextQuads(quads);\n"
     "  for (auto& quad : quads) {  // Iris (font metrics)\n"
     "    quad = IrisFingerprint::ProtectQuad(owner_document_->GetExecutionContext(),\n"
     "                                        quad);\n"
     "  }\n\n"
     "  return MakeGarbageCollected<DOMRectList>(quads);\n",
     "quad = IrisFingerprint::ProtectQuad(", "Range.getClientRects")
edit(R, "  SyncScrollAttemptHeuristic::DidAccessScrollOffset();\n"
        "  return DOMRect::FromRectF(BoundingRect());\n}\n",
     "  SyncScrollAttemptHeuristic::DidAccessScrollOffset();\n"
     "  return DOMRect::FromRectF(IrisFingerprint::ProtectRect(  // Iris (font metrics)\n"
     "      owner_document_->GetExecutionContext(), BoundingRect()));\n}\n",
     "owner_document_->GetExecutionContext(), BoundingRect()));", "Range.getBoundingClientRect")
PY
echo "=== font-metric noise complete ==="
