// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): the "not available" SmsCodeBrowserClient that SmsCodeRetriever.getBrowserClient returns (null crashed 0.0.0.11).
// A plain class, so R8 sees it (a java.lang.reflect.Proxy here crashed the first 0.0.0.12 build at start-up:
// ClassCastException after R8). Every Task has already failed, collections are empty, the rest false/0/null.

package com.google.android.gms.auth.api.phone;

public final class IrisSmsCodeBrowserClient implements com.google.android.gms.auth.api.phone.SmsCodeBrowserClient {
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> startSmsCodeRetriever() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.common.api.internal.ApiKey<com.google.android.gms.common.api.Api.ApiOptions.NoOptions> getApiKey() { return null; }
}
