// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.jni_zero.JniType;
import org.jni_zero.NativeMethods;

import org.chromium.base.ApplicationState;
import org.chromium.base.ApplicationStatus;
import org.chromium.base.ContextUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.browser.init.ChromeBrowserInitializer;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Iris app lock on Android. The passphrase and the encryption it protects are the desktop design
 * (chrome/browser/iris/iris_app_lock.h): a random data key, wrapped by scrypt(passphrase), encrypts
 * cookies, bookmarks and sessions through IrisKeyProvider. There is no recovery.
 *
 * <p>Android parts: the "Iris is locked" screen ({@link IrisUnlockActivity}) is shown when Iris starts
 * and again after it has been in the background for {@link #RELOCK_AFTER_MS}; optional fingerprint
 * unlock keeps the passphrase only encrypted under an Android Keystore key that needs strong
 * biometrics (invalidated when fingerprints change).
 */
@NullMarked
public final class IrisAppLock {
    /** Mirror of the native iris.app_lock.enabled pref, readable before the browser has started. */
    static final String PREF_ENABLED = "iris_app_lock_enabled";

    private static final String PREF_BIO_CIPHERTEXT = "iris_app_lock_biometric_ciphertext";
    private static final String PREF_BIO_IV = "iris_app_lock_biometric_iv";
    private static final String KEY_ALIAS = "iris_app_lock_biometric";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    static final long RELOCK_AFTER_MS = 5 * 60 * 1000;

    /** Result codes of setPassphrase/remove (iris_app_lock::Result). */
    static final int RESULT_OK = 0;
    static final int RESULT_WRONG_PASSPHRASE = 1;
    static final int RESULT_EMPTY_PASSPHRASE = 2;

    private static boolean sUnlocked;
    private static boolean sShowing;
    private static boolean sListening;
    private static boolean sSyncScheduled;
    private static long sBackgroundSince = -1;

    private IrisAppLock() {}

    private static SharedPreferences prefs() {
        return ContextUtils.getAppSharedPreferences();
    }

    /** Whether the lock is on (mirror; kept in sync with the native pref once the browser runs). */
    public static boolean isLockSet() {
        return prefs().getBoolean(PREF_ENABLED, false);
    }

    /** Called by every Iris activity when it resumes: shows the unlock screen when needed. */
    public static void maybeShowLock(Activity activity) {
        ensureListening();
        scheduleNativeSync(activity);
        if (!isLockSet() || sUnlocked || sShowing) return;
        sShowing = true;
        Intent intent = new Intent(activity, IrisUnlockActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION);
        activity.startActivity(intent);
    }

    static void onUnlocked() {
        sUnlocked = true;
        sShowing = false;
        sBackgroundSince = -1;
    }

    static void onUnlockScreenGone() {
        sShowing = false;
    }

    // Re-lock after RELOCK_AFTER_MS in the background (all Iris activities stopped).
    private static void ensureListening() {
        if (sListening) return;
        sListening = true;
        ApplicationStatus.registerApplicationStateListener(
                newState -> {
                    if (newState == ApplicationState.HAS_STOPPED_ACTIVITIES
                            || newState == ApplicationState.HAS_DESTROYED_ACTIVITIES) {
                        if (sBackgroundSince < 0) sBackgroundSince = SystemClock.elapsedRealtime();
                    } else if (newState == ApplicationState.HAS_RUNNING_ACTIVITIES) {
                        if (sBackgroundSince >= 0
                                && SystemClock.elapsedRealtime() - sBackgroundSince
                                        >= RELOCK_AFTER_MS) {
                            sUnlocked = false;
                        }
                        sBackgroundSince = -1;
                    }
                });
    }

    // The native pref is the truth: once the browser runs, make the mirror match it (and lock if the
    // native lock is on but the mirror missed it, so the key provider is never left waiting unseen).
    private static void scheduleNativeSync(Activity activity) {
        if (sSyncScheduled) return;
        sSyncScheduled = true;
        ChromeBrowserInitializer.getInstance()
                .runNowOrAfterFullBrowserStarted(
                        () -> {
                            boolean nativeOn = IrisAppLockJni.get().isEnabled();
                            if (nativeOn != isLockSet()) {
                                prefs().edit().putBoolean(PREF_ENABLED, nativeOn).apply();
                            }
                            if (nativeOn && !sUnlocked && !sShowing && !activity.isFinishing()) {
                                maybeShowLock(activity);
                            }
                        });
    }

    // ---- passphrase (native, scrypt: slow on purpose) ----

    static boolean unlock(String passphrase) {
        return IrisAppLockJni.get().unlock(passphrase);
    }

    static boolean nativeIsEnabled() {
        return IrisAppLockJni.get().isEnabled();
    }

    /** Sets (lock off) or changes (lock on) the passphrase. Changing it turns fingerprint unlock off. */
    static int setPassphrase(String current, String newPassphrase) {
        boolean wasOn = isLockSet();
        int result = IrisAppLockJni.get().setPassphrase(current, newPassphrase);
        if (result == RESULT_OK) {
            prefs().edit().putBoolean(PREF_ENABLED, true).apply();
            sUnlocked = true;
            if (wasOn) clearBiometric();
        }
        return result;
    }

    static int remove(String current) {
        int result = IrisAppLockJni.get().remove(current);
        if (result == RESULT_OK) {
            prefs().edit().putBoolean(PREF_ENABLED, false).apply();
            clearBiometric();
        }
        return result;
    }

    // ---- fingerprint (Android Keystore; the passphrase is stored only encrypted) ----

    static boolean isBiometricSet() {
        return prefs().getString(PREF_BIO_CIPHERTEXT, null) != null;
    }

    private static SecretKey getOrCreateKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.getKey(KEY_ALIAS, null) instanceof SecretKey key) return key;
        KeyGenParameterSpec.Builder spec =
                new KeyGenParameterSpec.Builder(
                                KEY_ALIAS,
                                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setUserAuthenticationRequired(true)
                        .setInvalidatedByBiometricEnrollment(true);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG);
        }
        KeyGenerator generator =
                KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(spec.build());
        return generator.generateKey();
    }

    /** A cipher to unlock with BiometricPrompt before {@link #storeBiometric}; null on failure. */
    static @Nullable Cipher encryptCipher() {
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey());
            return cipher;
        } catch (Exception e) {
            return null;
        }
    }

    /** A cipher to unlock with BiometricPrompt before {@link #readBiometric}; null if unusable. */
    static @Nullable Cipher decryptCipher() {
        String iv = prefs().getString(PREF_BIO_IV, null);
        if (iv == null) return null;
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(
                    Cipher.DECRYPT_MODE,
                    getOrCreateKey(),
                    new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            return cipher;
        } catch (KeyPermanentlyInvalidatedException e) {
            clearBiometric(); // fingerprints changed: passphrase needed again
            return null;
        } catch (Exception e) {
            return null;
        }
    }

    static boolean storeBiometric(Cipher authenticatedCipher, String passphrase) {
        try {
            byte[] sealed =
                    authenticatedCipher.doFinal(passphrase.getBytes(StandardCharsets.UTF_8));
            prefs().edit()
                    .putString(PREF_BIO_CIPHERTEXT, Base64.encodeToString(sealed, Base64.NO_WRAP))
                    .putString(
                            PREF_BIO_IV,
                            Base64.encodeToString(authenticatedCipher.getIV(), Base64.NO_WRAP))
                    .apply();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    static @Nullable String readBiometric(Cipher authenticatedCipher) {
        String sealed = prefs().getString(PREF_BIO_CIPHERTEXT, null);
        if (sealed == null) return null;
        try {
            return new String(
                    authenticatedCipher.doFinal(Base64.decode(sealed, Base64.NO_WRAP)),
                    StandardCharsets.UTF_8);
        } catch (Exception e) {
            return null;
        }
    }

    static void clearBiometric() {
        prefs().edit().remove(PREF_BIO_CIPHERTEXT).remove(PREF_BIO_IV).apply();
        try {
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            keyStore.deleteEntry(KEY_ALIAS);
        } catch (Exception e) {
            // Nothing stored: fine.
        }
    }

    @NativeMethods
    interface Natives {
        boolean isEnabled();

        boolean unlock(@JniType("std::u16string") String passphrase);

        int setPassphrase(
                @JniType("std::u16string") String current,
                @JniType("std::u16string") String newPassphrase);

        int remove(@JniType("std::u16string") String current);
    }
}
