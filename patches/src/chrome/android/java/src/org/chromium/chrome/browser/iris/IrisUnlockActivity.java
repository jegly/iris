// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.window.OnBackInvokedDispatcher;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.init.ChromeBrowserInitializer;
import org.chromium.chrome.browser.night_mode.NightModeUtils;
import org.chromium.chrome.browser.night_mode.ThemeType;

import javax.crypto.Cipher;

/**
 * "Iris is locked": shown over Iris when it starts and after time in the background (IrisAppLock).
 * Unlocks with the passphrase (checked by the native app lock, scrypt) or, if set up, a fingerprint.
 * Back sends Iris to the background instead of closing the lock.
 */
@NullMarked
public class IrisUnlockActivity extends Activity {
    private @Nullable EditText mPassphrase;
    private @Nullable Button mUnlock;
    private @Nullable Button mFingerprint;
    private @Nullable TextView mMessage;
    private boolean mUnlocked;
    private boolean mBrowserReady;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);

        // Same colours as the rest of Iris: the chosen palette (Settings > Appearance), light or dark.
        boolean night = isNightMode();
        int overlay = IrisPalettes.overlayFor(night);
        if (overlay != 0) getTheme().applyStyle(overlay, true);
        int surface = themeColor(R.attr.colorSurface, night ? 0xFF1E1E2E : 0xFFFFFFFF);
        int onSurface = themeColor(R.attr.colorOnSurface, night ? 0xFFCDD6F4 : 0xFF1B1B1F);
        int primary = themeColor(R.attr.colorPrimary, 0xFF6750A4);
        int onPrimary = themeColor(R.attr.colorOnPrimary, 0xFFFFFFFF);
        getWindow().getDecorView().setBackgroundColor(surface);

        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);
        layout.setPadding(pad, pad, pad, pad);
        layout.setBackgroundColor(surface);

        TextView title = new TextView(this);
        title.setText("Iris is locked");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER);
        title.setTextColor(onSurface);
        layout.addView(title);

        EditText passphrase = new EditText(this);
        passphrase.setHint("Passphrase");
        passphrase.setTextColor(onSurface);
        passphrase.setHintTextColor((onSurface & 0x00FFFFFF) | 0x80000000);
        passphrase.setBackgroundTintList(ColorStateList.valueOf(primary));
        passphrase.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        passphrase.setImeOptions(EditorInfo.IME_ACTION_DONE);
        passphrase.setOnEditorActionListener(
                (v, actionId, event) -> {
                    if (actionId != EditorInfo.IME_ACTION_DONE) return false;
                    unlockWithPassphrase();
                    return true;
                });
        layout.addView(passphrase);
        mPassphrase = passphrase;

        Button unlock = new Button(this);
        unlock.setText("Unlock");
        unlock.setEnabled(false);
        styleButton(unlock, primary, onPrimary);
        unlock.setOnClickListener(v -> unlockWithPassphrase());
        layout.addView(unlock);
        mUnlock = unlock;

        Button fingerprint = new Button(this);
        fingerprint.setText("Use fingerprint");
        fingerprint.setVisibility(View.GONE);
        styleButton(fingerprint, primary, onPrimary);
        fingerprint.setOnClickListener(v -> unlockWithFingerprint());
        layout.addView(fingerprint);
        mFingerprint = fingerprint;

        TextView message = new TextView(this);
        message.setGravity(Gravity.CENTER);
        message.setTextColor(onSurface);
        message.setText("Starting…");
        layout.addView(message);
        mMessage = message;

        setContentView(layout);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getOnBackInvokedDispatcher()
                    .registerOnBackInvokedCallback(
                            OnBackInvokedDispatcher.PRIORITY_DEFAULT, () -> moveTaskToBack(true));
        }

        // The passphrase is checked by the browser's native app lock: wait until it has started.
        ChromeBrowserInitializer.getInstance().runNowOrAfterFullBrowserStarted(this::onBrowserReady);
    }

    private boolean isNightMode() {
        int theme = NightModeUtils.getThemeSetting();
        if (theme == ThemeType.DARK) return true;
        if (theme == ThemeType.LIGHT) return false;
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
    }

    private int themeColor(int attr, int fallback) {
        TypedValue value = new TypedValue();
        if (getTheme().resolveAttribute(attr, value, true)
                && value.type >= TypedValue.TYPE_FIRST_COLOR_INT
                && value.type <= TypedValue.TYPE_LAST_COLOR_INT) {
            return value.data;
        }
        return fallback;
    }

    private static void styleButton(Button button, int background, int text) {
        int dim = (background & 0x00FFFFFF) | 0x61000000; // 38% when disabled
        button.setBackgroundTintList(
                new ColorStateList(
                        new int[][] {{-android.R.attr.state_enabled}, {}},
                        new int[] {dim, background}));
        button.setTextColor(
                new ColorStateList(
                        new int[][] {{-android.R.attr.state_enabled}, {}},
                        new int[] {(text & 0x00FFFFFF) | 0x99000000, text}));
    }

    private void onBrowserReady() {
        if (isFinishing()) return;
        mBrowserReady = true;
        if (!IrisAppLock.nativeIsEnabled()) {
            // Lock is not actually on (mirror was stale): nothing to unlock.
            finishUnlocked();
            return;
        }
        if (mUnlock != null) mUnlock.setEnabled(true);
        setMessage("");
        if (IrisAppLock.isBiometricSet() && mFingerprint != null) {
            mFingerprint.setVisibility(View.VISIBLE);
            unlockWithFingerprint();
        }
    }

    private void setMessage(String text) {
        if (mMessage != null) mMessage.setText(text);
    }

    private void unlockWithPassphrase() {
        if (!mBrowserReady || mPassphrase == null) return;
        String passphrase = mPassphrase.getText().toString();
        mPassphrase.setText("");
        if (passphrase.isEmpty()) return;
        if (IrisAppLock.unlock(passphrase)) {
            finishUnlocked();
        } else {
            setMessage("Wrong passphrase");
        }
    }

    private void unlockWithFingerprint() {
        Cipher cipher = IrisAppLock.decryptCipher();
        if (cipher == null) {
            if (mFingerprint != null) mFingerprint.setVisibility(View.GONE);
            setMessage("Fingerprint unlock is off (fingerprints changed). Use your passphrase.");
            return;
        }
        BiometricPrompt.Builder builder =
                new BiometricPrompt.Builder(this)
                        .setTitle("Unlock Iris")
                        .setNegativeButton(
                                "Use passphrase", getMainExecutor(), (dialog, which) -> {});
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG);
        }
        builder.build()
                .authenticate(
                        new BiometricPrompt.CryptoObject(cipher),
                        new CancellationSignal(),
                        getMainExecutor(),
                        new BiometricPrompt.AuthenticationCallback() {
                            @Override
                            public void onAuthenticationSucceeded(
                                    BiometricPrompt.AuthenticationResult result) {
                                BiometricPrompt.CryptoObject crypto = result.getCryptoObject();
                                Cipher authenticated = crypto == null ? null : crypto.getCipher();
                                String passphrase =
                                        authenticated == null
                                                ? null
                                                : IrisAppLock.readBiometric(authenticated);
                                if (passphrase != null && IrisAppLock.unlock(passphrase)) {
                                    finishUnlocked();
                                } else {
                                    setMessage("Fingerprint unlock failed. Use your passphrase.");
                                }
                            }
                        });
    }

    private void finishUnlocked() {
        mUnlocked = true;
        IrisAppLock.onUnlocked();
        finish();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        moveTaskToBack(true); // never closes the lock
    }

    @Override
    protected void onDestroy() {
        if (!mUnlocked) IrisAppLock.onUnlockScreenGone();
        super.onDestroy();
    }
}
