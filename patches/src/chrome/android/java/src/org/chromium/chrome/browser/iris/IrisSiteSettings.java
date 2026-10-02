// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import org.jni_zero.JniType;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.profiles.Profile;

/**
 * Iris per-site settings on Android: "Browser identity" (iris_user_agent) and "Canvas and audio
 * reading" (iris_fingerprint_host), the same website settings desktop Iris uses.
 */
@NullMarked
public final class IrisSiteSettings {
    private IrisSiteSettings() {}

    /** "" = Iris (default), "firefox_linux", "chrome_windows" or "safari_mac". */
    public static String getUserAgentPreset(Profile profile, String origin) {
        return IrisSiteSettingsJni.get().getUserAgentPreset(profile, origin);
    }

    public static void setUserAgentPreset(Profile profile, String origin, String preset) {
        IrisSiteSettingsJni.get().setUserAgentPreset(profile, origin, preset);
    }

    /** "protected" (default), "blank" or "real". */
    public static String getFingerprintReadsPreset(Profile profile, String origin) {
        return IrisSiteSettingsJni.get().getFingerprintReadsPreset(profile, origin);
    }

    public static void setFingerprintReadsPreset(Profile profile, String origin, String preset) {
        IrisSiteSettingsJni.get().setFingerprintReadsPreset(profile, origin, preset);
    }

    @NativeMethods
    interface Natives {
        @JniType("std::string")
        String getUserAgentPreset(
                @JniType("Profile*") Profile profile, @JniType("std::string") String origin);

        void setUserAgentPreset(
                @JniType("Profile*") Profile profile,
                @JniType("std::string") String origin,
                @JniType("std::string") String preset);

        @JniType("std::string")
        String getFingerprintReadsPreset(
                @JniType("Profile*") Profile profile, @JniType("std::string") String origin);

        void setFingerprintReadsPreset(
                @JniType("Profile*") Profile profile,
                @JniType("std::string") String origin,
                @JniType("std::string") String preset);
    }
}
