// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

#include "third_party/blink/renderer/core/html/canvas/iris_fingerprint.h"

#include <bit>
#include <cmath>

#include "base/rand_util.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/platform/graphics/static_bitmap_image.h"
#include "third_party/blink/renderer/platform/graphics/unaccelerated_static_bitmap_image.h"
#include "third_party/skia/include/core/SkData.h"
#include "third_party/skia/include/core/SkImage.h"

namespace blink {

namespace {

using Mode = mojom::blink::IrisFingerprintMode;

uint64_t Mix(uint64_t x) {  // splitmix64
  x += 0x9E3779B97F4A7C15ull;
  x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ull;
  x = (x ^ (x >> 27)) * 0x94D049BB133111EBull;
  return x ^ (x >> 31);
}

IrisFingerprint* For(ExecutionContext* context) {
  return context ? IrisFingerprint::From(*context) : nullptr;
}

}  // namespace

const char IrisFingerprint::kSupplementName[] = "IrisFingerprint";

// static
IrisFingerprint* IrisFingerprint::From(ExecutionContext& context) {
  auto* fp = Supplement<ExecutionContext>::From<IrisFingerprint>(context);
  if (!fp) {
    fp = MakeGarbageCollected<IrisFingerprint>(context);
    Supplement<ExecutionContext>::ProvideTo(context, fp);
  }
  return fp;
}

IrisFingerprint::IrisFingerprint(ExecutionContext& context)
    : Supplement<ExecutionContext>(context) {}

void IrisFingerprint::Trace(Visitor* visitor) const {
  Supplement<ExecutionContext>::Trace(visitor);
}

void IrisFingerprint::EnsureLoaded() {
  if (loaded_) {
    return;
  }
  loaded_ = true;
  seed_ = base::RandUint64();  // fallback (workers, closed pipe)
  auto* window = DynamicTo<LocalDOMWindow>(GetSupplementable());
  LocalFrame* frame = window ? window->GetFrame() : nullptr;
  if (!frame) {
    return;
  }
  mojo::Remote<mojom::blink::IrisFingerprintHost> host;
  frame->GetBrowserInterfaceBroker().GetInterface(
      host.BindNewPipeAndPassReceiver());
  Mode mode = Mode::kProtected;
  uint64_t seed = 0;
  if (host->GetMode(&mode, &seed)) {
    mode_ = mode;
    seed_ = seed;
  }
}

// static
void IrisFingerprint::ProtectRGBA8(ExecutionContext* context,
                                   base::span<uint8_t> rgba) {
  IrisFingerprint* fp = For(context);
  if (!fp) {
    return;
  }
  fp->EnsureLoaded();
  if (fp->mode_ == Mode::kReal) {
    return;
  }
  if (fp->mode_ == Mode::kBlank) {
    std::fill(rgba.begin(), rgba.end(), 0);
    return;
  }
  const size_t pixels = rgba.size() / 4;
  for (size_t i = 0; i < pixels; ++i) {
    base::span<uint8_t> px = rgba.subspan(i * 4, 4u);
    if (px[3] == 0) {
      continue;  // leave fully transparent pixels untouched
    }
    const uint64_t h = Mix(fp->seed_ ^ (i * 0xD1B54A32D192ED03ull));
    if ((h & 7) != 0) {
      continue;  // about 1 pixel in 8
    }
    const size_t channel = (h >> 3) % 3;
    px[channel] = static_cast<uint8_t>((px[channel] & 0xFE) | ((h >> 8) & 1));
  }
}

// static
scoped_refptr<StaticBitmapImage> IrisFingerprint::ProtectImage(
    ExecutionContext* context,
    scoped_refptr<StaticBitmapImage> image) {
  IrisFingerprint* fp = For(context);
  if (!fp || !image) {
    return image;
  }
  fp->EnsureLoaded();
  if (fp->mode_ == Mode::kReal) {
    return image;
  }
  const gfx::Size size = image->GetSize();
  if (size.IsEmpty()) {
    return image;
  }
  const SkImageInfo info =
      SkImageInfo::Make(size.width(), size.height(), kRGBA_8888_SkColorType,
                        kUnpremul_SkAlphaType);
  Vector<uint8_t> pixels = image->CopyImageData(info, /*apply_orientation=*/false);
  if (pixels.empty() || pixels.size() != info.computeMinByteSize()) {
    return image;
  }
  ProtectRGBA8(context, base::span(pixels));
  sk_sp<SkImage> protected_image = SkImages::RasterFromData(
      info, SkData::MakeWithCopy(pixels.data(), pixels.size()),
      info.minRowBytes());
  if (!protected_image) {
    return image;
  }
  return UnacceleratedStaticBitmapImage::Create(std::move(protected_image));
}

// static
void IrisFingerprint::ProtectAudio(ExecutionContext* context,
                                   base::span<float> samples,
                                   size_t first_index) {
  IrisFingerprint* fp = For(context);
  if (!fp) {
    return;
  }
  fp->EnsureLoaded();
  if (fp->mode_ == Mode::kReal) {
    return;
  }
  if (fp->mode_ == Mode::kBlank) {
    std::fill(samples.begin(), samples.end(), 0.0f);
    return;
  }
  for (size_t i = 0; i < samples.size(); ++i) {
    if (samples[i] == 0.0f || !std::isfinite(samples[i])) {
      continue;  // silence and -Infinity dB (analyser) stay as they are
    }
    uint32_t bits = std::bit_cast<uint32_t>(samples[i]);
    const uint64_t h =
        Mix(fp->seed_ ^ ((first_index + i) * 0x9E3779B97F4A7C15ull));
    bits = (bits & ~1u) | static_cast<uint32_t>(h & 1);  // idempotent
    samples[i] = std::bit_cast<float>(bits);
  }
}

// static
void IrisFingerprint::ProtectBytes(ExecutionContext* context,
                                   base::span<uint8_t> bytes) {
  IrisFingerprint* fp = For(context);
  if (!fp) {
    return;
  }
  fp->EnsureLoaded();
  if (fp->mode_ == Mode::kReal) {
    return;
  }
  if (fp->mode_ == Mode::kBlank) {
    std::fill(bytes.begin(), bytes.end(), 0);
    return;
  }
  for (size_t i = 0; i < bytes.size(); ++i) {
    if (bytes[i] == 0) {
      continue;
    }
    const uint64_t h = Mix(fp->seed_ ^ (i * 0xA0761D6478BD642Full));
    if ((h & 7) != 0) {
      continue;
    }
    bytes[i] = static_cast<uint8_t>((bytes[i] & 0xFE) | ((h >> 8) & 1));
  }
}

}  // namespace blink
