// Copyright 2026 jegly (Iris). Licensed under GPL-2.0-or-later.
// Iris: part of the Iris patch set (github.com/jegly/iris), applied on top of Chromium.

#ifndef CHROME_BROWSER_SSL_IRIS_TRACKING_PARAM_INTERCEPTOR_H_
#define CHROME_BROWSER_SSL_IRIS_TRACKING_PARAM_INTERCEPTOR_H_

#include <optional>

#include "base/memory/weak_ptr.h"
#include "content/public/browser/url_loader_request_interceptor.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "net/base/request_priority.h"
#include "net/http/http_request_headers.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "url/gurl.h"

// Removes known click and campaign tracking parameters (utm_*, fbclid, gclid,
// ...) from navigation URLs before the request is sent. The navigation is
// answered with an internal redirect to the cleaned URL, the same mechanism
// HttpsUpgradesInterceptor uses, so nothing reaches the network with the
// parameters attached. Interceptors run again on every redirect, so parameters
// added by a server redirect are removed too.
class IrisTrackingParamInterceptor
    : public content::URLLoaderRequestInterceptor,
      public network::mojom::URLLoader {
 public:
  IrisTrackingParamInterceptor();
  IrisTrackingParamInterceptor(const IrisTrackingParamInterceptor&) = delete;
  IrisTrackingParamInterceptor& operator=(const IrisTrackingParamInterceptor&) =
      delete;
  ~IrisTrackingParamInterceptor() override;

  // Returns `url` without tracking parameters, or nullopt if it has none.
  static std::optional<GURL> StripTrackingParams(const GURL& url);

  // content::URLLoaderRequestInterceptor:
  void MaybeCreateLoader(
      const network::ResourceRequest& tentative_resource_request,
      content::BrowserContext* browser_context,
      LoaderCallback callback) override;

  // network::mojom::URLLoader:
  void FollowRedirect(
      network::HttpRequestHeadersUpdateParams headers_update_params,
      const std::optional<GURL>& new_url) override {}
  void SetPriority(net::RequestPriority priority,
                   int intra_priority_value) override {}

 private:
  void RedirectHandler(
      const GURL& new_url,
      const network::ResourceRequest& request,
      mojo::PendingReceiver<network::mojom::URLLoader> receiver,
      mojo::PendingRemote<network::mojom::URLLoaderClient> client);
  void OnConnectionClosed();

  mojo::Receiver<network::mojom::URLLoader> receiver_{this};
  mojo::Remote<network::mojom::URLLoaderClient> client_;
  base::WeakPtrFactory<IrisTrackingParamInterceptor> weak_factory_{this};
};

#endif  // CHROME_BROWSER_SSL_IRIS_TRACKING_PARAM_INTERCEPTOR_H_
