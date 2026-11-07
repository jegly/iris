// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): the "not available" SplitInstallManager that SplitInstallManagerFactory.create returns (null crashed 0.0.0.11).
// A plain class, so R8 sees it (a java.lang.reflect.Proxy here crashed the first 0.0.0.12 build at start-up:
// ClassCastException after R8). Every Task has already failed, collections are empty, the rest false/0/null.

package com.google.android.play.core.splitinstall;

public final class IrisSplitInstallManager implements com.google.android.play.core.splitinstall.SplitInstallManager {
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> cancelInstall(int p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> deferredInstall(java.util.List<java.lang.String> p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> deferredLanguageInstall(java.util.List<java.util.Locale> p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> deferredLanguageUninstall(java.util.List<java.util.Locale> p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> deferredUninstall(java.util.List<java.lang.String> p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<com.google.android.play.core.splitinstall.SplitInstallSessionState> getSessionState(int p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.util.List<com.google.android.play.core.splitinstall.SplitInstallSessionState>> getSessionStates() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Integer> startInstall(com.google.android.play.core.splitinstall.SplitInstallRequest p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public java.util.Set<java.lang.String> getInstalledLanguages() { return java.util.Collections.emptySet(); }
  @Override public java.util.Set<java.lang.String> getInstalledModules() { return java.util.Collections.emptySet(); }
  @Override public void registerListener(com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener p0) {  }
  @Override public void unregisterListener(com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener p0) {  }
  @Override public boolean startConfirmationDialogForResult(com.google.android.play.core.splitinstall.SplitInstallSessionState p0, androidx.activity.result.ActivityResultLauncher<androidx.activity.result.IntentSenderRequest> p1) { return false; }
  @Override public boolean startConfirmationDialogForResult(com.google.android.play.core.splitinstall.SplitInstallSessionState p0, android.app.Activity p1, int p2) throws android.content.IntentSender.SendIntentException { return false; }
  @Override public boolean startConfirmationDialogForResult(com.google.android.play.core.splitinstall.SplitInstallSessionState p0, com.google.android.play.core.common.IntentSenderForResultStarter p1, int p2) throws android.content.IntentSender.SendIntentException { return false; }
  @Override public void zza(com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener p0) {  }
  @Override public void zzb(com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener p0) {  }
}
