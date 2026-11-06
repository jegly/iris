// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): every Task the Play services stubs hand out has already failed: failure and
// completion listeners run at once, success listeners never; results are never available.

package com.google.android.gms.tasks;

public final class IrisTasks {
  private IrisTasks() {}

  @SuppressWarnings("unchecked")
  public static <T> Task<T> failed() {
    return (Task<T>) FailedTask.INSTANCE;
  }

  private static final class FailedTask extends Task<Object> {
    static final FailedTask INSTANCE = new FailedTask();
    private static final Exception EXCEPTION =
        new IllegalStateException("Google Play services are not part of Iris");

    @Override public boolean isComplete() { return true; }
    @Override public boolean isSuccessful() { return false; }
    @Override public boolean isCanceled() { return false; }
    @Override public Object getResult() { throw new IllegalStateException(EXCEPTION); }
    @Override public <X extends Throwable> Object getResult(Class<X> p0) throws X {
      throw new IllegalStateException(EXCEPTION);
    }
    @Override public Exception getException() { return EXCEPTION; }
    @Override public Task<Object> addOnSuccessListener(OnSuccessListener<? super Object> p0) { return this; }
    @Override public Task<Object> addOnSuccessListener(
        java.util.concurrent.Executor p0, OnSuccessListener<? super Object> p1) { return this; }
    @Override public Task<Object> addOnSuccessListener(
        android.app.Activity p0, OnSuccessListener<? super Object> p1) { return this; }
    @Override public Task<Object> addOnFailureListener(OnFailureListener p0) {
      p0.onFailure(EXCEPTION);
      return this;
    }
    @Override public Task<Object> addOnFailureListener(
        java.util.concurrent.Executor p0, OnFailureListener p1) {
      p0.execute(() -> p1.onFailure(EXCEPTION));
      return this;
    }
    @Override public Task<Object> addOnFailureListener(android.app.Activity p0, OnFailureListener p1) {
      p1.onFailure(EXCEPTION);
      return this;
    }
    @Override public Task<Object> addOnCompleteListener(OnCompleteListener<Object> p0) {
      p0.onComplete(this);
      return this;
    }
    @Override public Task<Object> addOnCompleteListener(
        java.util.concurrent.Executor p0, OnCompleteListener<Object> p1) {
      p0.execute(() -> p1.onComplete(this));
      return this;
    }
    @Override public Task<Object> addOnCompleteListener(
        android.app.Activity p0, OnCompleteListener<Object> p1) {
      p1.onComplete(this);
      return this;
    }
  }
}
