// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): the "not available" ReviewManager that ReviewManagerFactory.create returns (null crashed 0.0.0.11).
// A plain class, so R8 sees it (a java.lang.reflect.Proxy here crashed the first 0.0.0.12 build at start-up:
// ClassCastException after R8). Every Task has already failed, collections are empty, the rest false/0/null.

package com.google.android.play.core.review;

public final class IrisReviewManager implements com.google.android.play.core.review.ReviewManager {
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> launchReviewFlow(android.app.Activity p0, com.google.android.play.core.review.ReviewInfo p1) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<com.google.android.play.core.review.ReviewInfo> requestReviewFlow() { return com.google.android.gms.tasks.IrisTasks.failed(); }
}
