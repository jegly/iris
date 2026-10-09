// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B4): canvas and audio fingerprint protection. Pages that read what they drew (getImageData, toDataURL,
// toBlob, OffscreenCanvas.convertToBlob) or the samples of an AudioBuffer get, depending on the site's setting:
//   protected (default): the lowest bit of some pixel channels / audio samples is set to a value derived from a
//                        per-site, per-session seed. Invisible and inaudible, stable within a session, idempotent
//                        (reading twice gives the same result), different per site and per Iris restart.
//   blank: empty data.  real: unchanged.
// Also covered: WebGL readPixels (RGBA bytes, on sites where WebGL is allowed) and AnalyserNode frequency /
// time-domain data (float and byte).
// The mode and seed come from the browser once per document (blink.mojom.IrisFingerprintHost, sync). Workers, which
// have no frame broker here, use "protected" with a random seed.

#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_CANVAS_IRIS_FINGERPRINT_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_CANVAS_IRIS_FINGERPRINT_H_

#include <cstdint>

#include "base/containers/span.h"
#include "base/memory/scoped_refptr.h"
#include "third_party/blink/public/mojom/iris/iris_fingerprint.mojom-blink.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/supplementable.h"

namespace blink {

class ExecutionContext;
class StaticBitmapImage;

class CORE_EXPORT IrisFingerprint final
    : public GarbageCollected<IrisFingerprint>,
      public Supplement<ExecutionContext> {
 public:
  static const char kSupplementName[];
  static IrisFingerprint* From(ExecutionContext&);

  explicit IrisFingerprint(ExecutionContext&);

  // Unpremultiplied RGBA8 pixels, in place.
  static void ProtectRGBA8(ExecutionContext*, base::span<uint8_t> rgba);
  // A copy with protected pixels (or `image` itself for "real" / failure).
  static scoped_refptr<StaticBitmapImage> ProtectImage(
      ExecutionContext*,
      scoped_refptr<StaticBitmapImage> image);
  // Audio samples, in place.
  // `first_index` = position of samples[0] in the AudioBuffer channel, so
  // getChannelData and copyFromChannel(offset) agree.
  static void ProtectAudio(ExecutionContext*,
                           base::span<float> samples,
                           size_t first_index = 0);

  // Byte samples (AnalyserNode byte data), in place: the lowest bit of about
  // one value in eight; zero values (silence) stay zero.
  static void ProtectBytes(ExecutionContext*, base::span<uint8_t> bytes);

  // "Block third-party requests": whether this document's third-party subresource requests are refused (asked from the
  // browser once, then cached for the document).
  static bool ShouldBlockThirdParty(ExecutionContext*);

  void Trace(Visitor*) const override;

 private:
  void EnsureLoaded();

  bool loaded_ = false;
  mojom::blink::IrisFingerprintMode mode_ =
      mojom::blink::IrisFingerprintMode::kProtected;
  uint64_t seed_ = 0;
  bool block_third_party_loaded_ = false;
  bool block_third_party_ = false;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_CANVAS_IRIS_FINGERPRINT_H_
