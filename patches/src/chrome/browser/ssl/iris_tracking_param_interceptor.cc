// Copyright 2026 jegly (Iris). Licensed under GPL-2.0-or-later.
// Iris: part of the Iris patch set (github.com/jegly/iris), applied on top of Chromium.

#include "chrome/browser/ssl/iris_tracking_param_interceptor.h"

#include <string>
#include <string_view>
#include <vector>

#include "base/containers/fixed_flat_set.h"
#include "base/functional/bind.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/stringprintf.h"
#include "base/time/time.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "net/http/http_response_headers.h"
#include "net/http/http_status_code.h"
#include "net/http/http_util.h"
#include "net/url_request/redirect_info.h"
#include "services/network/public/mojom/url_response_head.mojom.h"

namespace {

// Parameters that only identify an ad click or a campaign, never page content.
// Any parameter starting with "utm_" is removed as well.
constexpr auto kTrackingParams = base::MakeFixedFlatSet<std::string_view>({
    "_hsenc",  "_hsmi",       "dclid",      "fbclid",     "gbraid",
    "gclid",   "gclsrc",      "igshid",     "li_fat_id",  "mc_eid",
    "mkt_tok", "msclkid",     "oly_anon_id", "oly_enc_id", "rb_clickid",
    "ttclid",  "twclid",      "vero_id",    "wbraid",     "yclid",
});

bool IsTrackingParam(std::string_view key) {
  const std::string lower = base::ToLowerASCII(key);
  return base::StartsWith(lower, "utm_") || kTrackingParams.contains(lower);
}

// Mirrors SetupRedirect() in https_upgrades_interceptor.cc: an artificial 307
// that the navigation follows without contacting the network.
net::RedirectInfo SetupRedirect(const network::ResourceRequest& request,
                                const GURL& new_url,
                                network::mojom::URLResponseHead* response_head) {
  response_head->encoded_data_length = 0;
  response_head->request_start = base::TimeTicks::Now();
  response_head->response_start = response_head->request_start;
  std::string header_string = base::StringPrintf(
      "HTTP/1.1 %i Temporary Redirect\n"
      "Location: %s\n"
      "Non-Authoritative-Reason: IrisTrackingParams\n",
      net::HTTP_TEMPORARY_REDIRECT, new_url.spec().c_str());
  response_head->headers = base::MakeRefCounted<net::HttpResponseHeaders>(
      net::HttpUtil::AssembleRawHeaders(header_string));
  return net::RedirectInfo::ComputeRedirectInfo(
      request.method, request.url, request.site_for_cookies,
      request.update_first_party_url_on_redirect
          ? net::RedirectInfo::FirstPartyURLPolicy::UPDATE_URL_ON_REDIRECT
          : net::RedirectInfo::FirstPartyURLPolicy::NEVER_CHANGE_URL,
      request.referrer_policy, request.referrer.spec(),
      request.request_initiator, net::HTTP_TEMPORARY_REDIRECT, new_url,
      /*referrer_policy_header=*/std::nullopt,
      /*insecure_scheme_was_upgraded=*/false);
}

}  // namespace

IrisTrackingParamInterceptor::IrisTrackingParamInterceptor() = default;

IrisTrackingParamInterceptor::~IrisTrackingParamInterceptor() = default;

// static
std::optional<GURL> IrisTrackingParamInterceptor::StripTrackingParams(
    const GURL& url) {
  if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS() || !url.has_query()) {
    return std::nullopt;
  }
  std::vector<std::string_view> kept;
  bool removed = false;
  for (std::string_view part :
       base::SplitStringPiece(url.query(), "&", base::KEEP_WHITESPACE,
                              base::SPLIT_WANT_ALL)) {
    const std::string_view key = part.substr(0, part.find('='));
    if (!key.empty() && IsTrackingParam(key)) {
      removed = true;
      continue;
    }
    kept.push_back(part);
  }
  if (!removed) {
    return std::nullopt;
  }
  const std::string query = base::JoinString(kept, "&");
  GURL::Replacements replacements;
  if (query.empty()) {
    replacements.ClearQuery();
  } else {
    replacements.SetQueryStr(query);
  }
  return url.ReplaceComponents(replacements);
}

void IrisTrackingParamInterceptor::MaybeCreateLoader(
    const network::ResourceRequest& tentative_resource_request,
    content::BrowserContext* browser_context,
    LoaderCallback callback) {
  std::optional<GURL> clean_url;
  if (tentative_resource_request.method ==
      net::HttpRequestHeaders::kGetMethod) {
    clean_url = StripTrackingParams(tentative_resource_request.url);
  }
  if (!clean_url) {
    std::move(callback).Run({});
    return;
  }
  std::move(callback).Run(
      base::BindOnce(&IrisTrackingParamInterceptor::RedirectHandler,
                     weak_factory_.GetWeakPtr(), *clean_url));
}

void IrisTrackingParamInterceptor::RedirectHandler(
    const GURL& new_url,
    const network::ResourceRequest& request,
    mojo::PendingReceiver<network::mojom::URLLoader> receiver,
    mojo::PendingRemote<network::mojom::URLLoaderClient> client) {
  receiver_.reset();
  client_.reset();
  receiver_.Bind(std::move(receiver));
  receiver_.set_disconnect_handler(
      base::BindOnce(&IrisTrackingParamInterceptor::OnConnectionClosed,
                     weak_factory_.GetWeakPtr()));
  client_.Bind(std::move(client));

  auto response_head = network::mojom::URLResponseHead::New();
  net::RedirectInfo redirect_info =
      SetupRedirect(request, new_url, response_head.get());
  client_->OnReceiveRedirect(redirect_info, std::move(response_head));
}

void IrisTrackingParamInterceptor::OnConnectionClosed() {
  receiver_.reset();
  client_.reset();
}
