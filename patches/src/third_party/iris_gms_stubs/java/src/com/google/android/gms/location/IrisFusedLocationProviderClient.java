// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.
// Iris (apply-android-gms-stubs.sh): the "not available" FusedLocationProviderClient that LocationServices.getFusedLocationProviderClient returns (null crashed 0.0.0.11).
// A plain class, so R8 sees it (a java.lang.reflect.Proxy here crashed the first 0.0.0.12 build at start-up:
// ClassCastException after R8). Every Task has already failed, collections are empty, the rest false/0/null.

package com.google.android.gms.location;

public final class IrisFusedLocationProviderClient implements com.google.android.gms.location.FusedLocationProviderClient {
  @Override public com.google.android.gms.tasks.Task<android.location.Location> getLastLocation() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<android.location.Location> getLastLocation(com.google.android.gms.location.LastLocationRequest p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<android.location.Location> getCurrentLocation(int p0, com.google.android.gms.tasks.CancellationToken p1) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<android.location.Location> getCurrentLocation(com.google.android.gms.location.CurrentLocationRequest p0, com.google.android.gms.tasks.CancellationToken p1) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<com.google.android.gms.location.LocationAvailability> getLocationAvailability() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestLocationUpdates(com.google.android.gms.location.LocationRequest p0, java.util.concurrent.Executor p1, com.google.android.gms.location.LocationListener p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestLocationUpdates(com.google.android.gms.location.LocationRequest p0, com.google.android.gms.location.LocationListener p1, android.os.Looper p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestLocationUpdates(com.google.android.gms.location.LocationRequest p0, com.google.android.gms.location.LocationCallback p1, android.os.Looper p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestLocationUpdates(com.google.android.gms.location.LocationRequest p0, java.util.concurrent.Executor p1, com.google.android.gms.location.LocationCallback p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestLocationUpdates(com.google.android.gms.location.LocationRequest p0, android.app.PendingIntent p1) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> removeLocationUpdates(com.google.android.gms.location.LocationListener p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> removeLocationUpdates(com.google.android.gms.location.LocationCallback p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> removeLocationUpdates(android.app.PendingIntent p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> flushLocations() { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> setMockMode(boolean p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> setMockLocation(android.location.Location p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestDeviceOrientationUpdates(com.google.android.gms.location.DeviceOrientationRequest p0, java.util.concurrent.Executor p1, com.google.android.gms.location.DeviceOrientationListener p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> requestDeviceOrientationUpdates(com.google.android.gms.location.DeviceOrientationRequest p0, com.google.android.gms.location.DeviceOrientationListener p1, android.os.Looper p2) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.tasks.Task<java.lang.Void> removeDeviceOrientationUpdates(com.google.android.gms.location.DeviceOrientationListener p0) { return com.google.android.gms.tasks.IrisTasks.failed(); }
  @Override public com.google.android.gms.common.api.internal.ApiKey<com.google.android.gms.common.api.Api.ApiOptions.NoOptions> getApiKey() { return null; }
}
