// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import org.jni_zero.CalledByNative;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.lifetime.ApplicationLifetime;

/**
 * App menu > "Exit" (apply-android-exit.sh): when "Clear browsing data when Iris starts" is on, the data is
 * cleared now, before the process ends (Chromium's ClearBrowsingDataForOnExitPolicy); then Iris quits the way a
 * restart without relaunch does (ApplicationLifetime: every activity finishes, the process is killed).
 */
@NullMarked
public final class IrisExit {
    private static boolean sExiting;

    private IrisExit() {}

    /** Clears (if set up) and quits. Repeated taps while it is working are ignored. */
    public static void exit() {
        if (sExiting) return;
        sExiting = true;
        IrisExitJni.get().clearThenExit();
    }

    @CalledByNative
    private static void onReadyToExit() {
        ApplicationLifetime.terminate(false);
    }

    @NativeMethods
    interface Natives {
        void clearThenExit();
    }
}
