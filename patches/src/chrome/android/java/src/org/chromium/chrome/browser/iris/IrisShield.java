// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import org.jni_zero.CalledByNative;
import org.jni_zero.JniType;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.content_public.browser.WebContents;

/**
 * The Android shield's link to the browser (iris_shield_android.cc): per-page counts from
 * iris::ShieldStats, the per-site switches from iris_shield_settings.h and the connection details,
 * the same sources as the desktop shield. An instance watches one tab's counts.
 */
@NullMarked
public final class IrisShield {
    // Same values as iris::shield::Switch (iris_shield_settings.h).
    public static final int ADS = 0;
    public static final int COOKIES = 1;
    public static final int JAVASCRIPT = 2;
    public static final int JIT = 3;
    public static final int WEBGL = 4;
    public static final int SIGN_IN = 5;
    public static final int FORGET = 6;
    public static final int RECOLOR = 7; // desktop only

    // Indexes into getCounts().
    public static final int TOTAL = 0;
    public static final int ADS_AND_TRACKERS = 1;
    public static final int COOKIE_COUNT = 2;
    public static final int FINGERPRINTS = 3;
    public static final int LIFETIME = 4;

    private final Runnable mOnChanged;
    private long mObserver;

    /** Calls {@code onChanged} on the UI thread whenever the counts of the tab change. */
    public IrisShield(WebContents webContents, Runnable onChanged) {
        mOnChanged = onChanged;
        mObserver = IrisShieldJni.get().init(this, webContents);
    }

    public void destroy() {
        if (mObserver != 0) {
            IrisShieldJni.get().destroy(mObserver);
            mObserver = 0;
        }
    }

    @CalledByNative
    private void onStatsChanged() {
        mOnChanged.run();
    }

    /** {total, ads and trackers, cookies, fingerprints, lifetime}. */
    public static int[] getCounts(@Nullable WebContents webContents) {
        if (webContents == null) return new int[5];
        return IrisShieldJni.get().getCounts(webContents);
    }

    /** One line per item, as in the desktop shield; "" when there are none. */
    public static String getConnectionDetails(@Nullable WebContents webContents) {
        if (webContents == null) return "";
        return IrisShieldJni.get().getConnectionDetails(webContents);
    }

    public static boolean isOn(Profile profile, String url, int which) {
        return IrisShieldJni.get().isOn(profile, url, which);
    }

    /** True when a global switch decides (e.g. "Turn WebGL off completely"). */
    public static boolean isLocked(Profile profile, int which) {
        return IrisShieldJni.get().isLocked(profile, which);
    }

    public static void set(Profile profile, String url, int which, boolean on) {
        IrisShieldJni.get().set(profile, url, which, on);
    }

    /** The master switch: ads and trackers, cross-site cookies and canvas/audio protection. */
    public static void setShield(Profile profile, String url, boolean on) {
        IrisShieldJni.get().setShield(profile, url, on);
    }

    public static void reset(Profile profile, String url) {
        IrisShieldJni.get().reset(profile, url);
    }

    @NativeMethods
    interface Natives {
        long init(
                IrisShield caller, @JniType("content::WebContents*") WebContents webContents);

        void destroy(long observerPtr);

        @JniType("std::vector<int32_t>")
        int[] getCounts(@JniType("content::WebContents*") WebContents webContents);

        @JniType("std::string")
        String getConnectionDetails(@JniType("content::WebContents*") WebContents webContents);

        boolean isOn(
                @JniType("Profile*") Profile profile,
                @JniType("std::string") String url,
                int which);

        boolean isLocked(@JniType("Profile*") Profile profile, int which);

        void set(
                @JniType("Profile*") Profile profile,
                @JniType("std::string") String url,
                int which,
                boolean on);

        void setShield(
                @JniType("Profile*") Profile profile,
                @JniType("std::string") String url,
                boolean on);

        void reset(@JniType("Profile*") Profile profile, @JniType("std::string") String url);
    }
}
