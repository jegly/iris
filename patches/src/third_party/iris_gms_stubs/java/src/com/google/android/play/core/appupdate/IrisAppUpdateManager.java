// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): the "not available" AppUpdateManager that AppUpdateManagerFactory.create returns (null crashed 0.0.0.11).
// A plain class, so R8 sees it (a java.lang.reflect.Proxy here crashed the first 0.0.0.12 build at start-up:
// ClassCastException after R8). Every Task has already failed, collections are empty, the rest false/0/null.

package com.google.android.play.core.appupdate;

public final class IrisAppUpdateManager implements com.google.android.play.core.appupdate.AppUpdateManager {
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> completeUpdate() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<com.google.android.play.core.appupdate.AppUpdateInfo> getAppUpdateInfo() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Integer> startUpdateFlow(com.google.android.play.core.appupdate.AppUpdateInfo p0, android.app.Activity p1, com.google.android.play.core.appupdate.AppUpdateOptions p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public void registerListener(com.google.android.play.core.install.InstallStateUpdatedListener p0) {  }
  @Override public void unregisterListener(com.google.android.play.core.install.InstallStateUpdatedListener p0) {  }
  @Override public boolean startUpdateFlowForResult(com.google.android.play.core.appupdate.AppUpdateInfo p0, androidx.activity.result.ActivityResultLauncher<androidx.activity.result.IntentSenderRequest> p1, com.google.android.play.core.appupdate.AppUpdateOptions p2) { return false; }
  @Override public boolean startUpdateFlowForResult(com.google.android.play.core.appupdate.AppUpdateInfo p0, int p1, android.app.Activity p2, int p3) throws android.content.IntentSender.SendIntentException { return false; }
  @Override public boolean startUpdateFlowForResult(com.google.android.play.core.appupdate.AppUpdateInfo p0, int p1, com.google.android.play.core.common.IntentSenderForResultStarter p2, int p3) throws android.content.IntentSender.SendIntentException { return false; }
  @Override public boolean startUpdateFlowForResult(com.google.android.play.core.appupdate.AppUpdateInfo p0, android.app.Activity p1, com.google.android.play.core.appupdate.AppUpdateOptions p2, int p3) throws android.content.IntentSender.SendIntentException { return false; }
  @Override public boolean startUpdateFlowForResult(com.google.android.play.core.appupdate.AppUpdateInfo p0, com.google.android.play.core.common.IntentSenderForResultStarter p1, com.google.android.play.core.appupdate.AppUpdateOptions p2, int p3) throws android.content.IntentSender.SendIntentException { return false; }
}
