// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
//
// Iris (Phase B4): browser side of canvas/audio fingerprint protection. Answers blink.mojom.IrisFingerprintHost
// per document: the top-level site's mode (website setting IRIS_FINGERPRINT_READS: "protected" (default), "blank",
// "real") and a seed = SHA-256(secret || site || off-the-record) where the secret is random per browser run, so
// noise is stable per site within a session, different across sites and across Iris restarts.

#ifndef CHROME_BROWSER_IRIS_IRIS_FINGERPRINT_HOST_H_
#define CHROME_BROWSER_IRIS_IRIS_FINGERPRINT_HOST_H_

#include <string>
#include <string_view>

#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "third_party/blink/public/mojom/iris/iris_fingerprint.mojom-forward.h"

class GURL;

namespace content {
class BrowserContext;
class RenderFrameHost;
}  // namespace content

namespace iris {

void BindFingerprintHost(
    content::RenderFrameHost* render_frame_host,
    mojo::PendingReceiver<blink::mojom::IrisFingerprintHost> receiver);

// Settings: "protected" | "blank" | "real".
std::string GetFingerprintReadsPreset(content::BrowserContext* context,
                                      const GURL& url);
void SetFingerprintReadsPreset(content::BrowserContext* context,
                               const GURL& url,
                               std::string_view preset);

}  // namespace iris

#endif  // CHROME_BROWSER_IRIS_IRIS_FINGERPRINT_HOST_H_
