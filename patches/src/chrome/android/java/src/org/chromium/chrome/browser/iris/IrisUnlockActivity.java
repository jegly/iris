// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.drawable.GradientDrawable;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.window.OnBackInvokedDispatcher;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.init.ChromeBrowserInitializer;
import org.chromium.chrome.browser.night_mode.NightModeUtils;
import org.chromium.chrome.browser.night_mode.ThemeType;

import javax.crypto.Cipher;

/**
 * The lock screen (app icon, passphrase box, fingerprint button; no text): shown over Iris when it starts and after time in the
 * background (IrisAppLock).
 * Unlocks with the passphrase (checked by the native app lock, scrypt) or, if set up, a fingerprint.
 * Back sends Iris to the background instead of closing the lock.
 */
@NullMarked
public class IrisUnlockActivity extends Activity {
    private @Nullable EditText mPassphrase;
    private @Nullable ImageButton mFingerprint;
    private int mError;
    private int mFieldColor;
    private float mDp;
    private boolean mUnlocked;
    private boolean mBrowserReady;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // No open/close animation: the lock appears and goes at once (jegly 2026-11-07, "no latency").
        noTransition();
        getWindow().setWindowAnimations(0);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);

        // Same colours as the rest of Iris: the chosen palette (Settings > Appearance), light or dark.
        boolean night = isNightMode();
        int overlay = IrisPalettes.overlayFor(night);
        if (overlay != 0) getTheme().applyStyle(overlay, true);
        int surface = themeColor(R.attr.colorSurface, night ? 0xFF1E1E2E : 0xFFFFFFFF);
        int onSurface = themeColor(R.attr.colorOnSurface, night ? 0xFFCDD6F4 : 0xFF1B1B1F);
        getWindow().getDecorView().setBackgroundColor(surface);

        // No text (jegly 2026-11-07): app icon, passphrase box, fingerprint button; Material 3
        // style in the palette's colours. Enter on the keyboard unlocks.
        float dp = getResources().getDisplayMetrics().density;
        int surfaceContainer =
                themeColor(R.attr.colorSurfaceContainerHighest, night ? 0xFF313244 : 0xFFE6E0E9);
        int secondaryContainer =
                themeColor(R.attr.colorSecondaryContainer, night ? 0xFF45475A : 0xFFE8DEF8);
        int onSecondaryContainer = themeColor(R.attr.colorOnSecondaryContainer, onSurface);
        mError = themeColor(R.attr.colorError, night ? 0xFFF38BA8 : 0xFFB3261E);
        mFieldColor = surfaceContainer;
        mDp = dp;

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);
        int pad = (int) (32 * dp);
        layout.setPadding(pad, pad, pad, pad);
        layout.setBackgroundColor(surface);

        ImageView icon = new ImageView(this);
        icon.setImageDrawable(getApplicationInfo().loadIcon(getPackageManager()));
        icon.setContentDescription("Iris"); // screen readers only, nothing is shown
        LinearLayout.LayoutParams iconParams =
                new LinearLayout.LayoutParams((int) (96 * dp), (int) (96 * dp));
        iconParams.bottomMargin = (int) (40 * dp);
        layout.addView(icon, iconParams);

        EditText passphrase = new EditText(this);
        passphrase.setTextColor(onSurface);
        passphrase.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        passphrase.setGravity(Gravity.CENTER);
        passphrase.setSingleLine(true);
        passphrase.setContentDescription("Passphrase"); // screen readers only
        passphrase.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        passphrase.setImeOptions(EditorInfo.IME_ACTION_DONE);
        passphrase.setPadding((int) (16 * dp), 0, (int) (16 * dp), 0);
        passphrase.setBackground(fieldBackground(false));
        passphrase.setOnEditorActionListener(
                (v, actionId, event) -> {
                    if (actionId != EditorInfo.IME_ACTION_DONE) return false;
                    unlockWithPassphrase();
                    return true;
                });
        passphrase.addTextChangedListener(
                new TextWatcher() {
                    @Override
                    public void beforeTextChanged(CharSequence t, int start, int count, int after) {}

                    @Override
                    public void onTextChanged(CharSequence t, int start, int before, int count) {
                        showError(false);
                    }

                    @Override
                    public void afterTextChanged(Editable e) {}
                });
        layout.addView(
                passphrase, new LinearLayout.LayoutParams((int) (280 * dp), (int) (56 * dp)));
        mPassphrase = passphrase;

        ImageButton fingerprint = new ImageButton(this);
        fingerprint.setImageResource(R.drawable.iris_fingerprint_24dp);
        fingerprint.setImageTintList(ColorStateList.valueOf(onSecondaryContainer));
        fingerprint.setContentDescription("Unlock with fingerprint"); // screen readers only
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(secondaryContainer);
        fingerprint.setBackground(circle);
        fingerprint.setScaleType(ImageView.ScaleType.CENTER);
        fingerprint.setVisibility(View.GONE);
        fingerprint.setOnClickListener(v -> unlockWithFingerprint());
        LinearLayout.LayoutParams fpParams =
                new LinearLayout.LayoutParams((int) (56 * dp), (int) (56 * dp));
        fpParams.topMargin = (int) (32 * dp);
        layout.addView(fingerprint, fpParams);
        mFingerprint = fingerprint;

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

    /** Material 3 filled field: rounded, no underline; a 2 dp error outline after a wrong try. */
    private GradientDrawable fieldBackground(boolean error) {
        GradientDrawable field = new GradientDrawable();
        field.setCornerRadius(16 * mDp);
        field.setColor(mFieldColor);
        if (error) field.setStroke((int) (2 * mDp), mError);
        return field;
    }

    private void showError(boolean error) {
        if (mPassphrase != null) mPassphrase.setBackground(fieldBackground(error));
    }

    private void onBrowserReady() {
        if (isFinishing()) return;
        mBrowserReady = true;
        if (!IrisAppLock.nativeIsEnabled()) {
            // Lock is not actually on (mirror was stale): nothing to unlock.
            finishUnlocked();
            return;
        }
        if (IrisAppLock.isBiometricSet() && mFingerprint != null) {
            mFingerprint.setVisibility(View.VISIBLE);
            unlockWithFingerprint();
        }
    }

    private void unlockWithPassphrase() {
        if (!mBrowserReady || mPassphrase == null) return;
        String passphrase = mPassphrase.getText().toString();
        mPassphrase.setText("");
        if (passphrase.isEmpty()) return;
        if (IrisAppLock.unlock(passphrase)) {
            finishUnlocked();
        } else {
            showError(true);
        }
    }

    private void unlockWithFingerprint() {
        Cipher cipher = IrisAppLock.decryptCipher();
        if (cipher == null) {
            if (mFingerprint != null) mFingerprint.setVisibility(View.GONE);
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
                                    showError(true);
                                }
                            }
                        });
    }

    private void finishUnlocked() {
        mUnlocked = true;
        IrisAppLock.onUnlocked();
        finish();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) noTransitionLegacy();
    }

    private void noTransition() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, 0, 0);
            overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0);
        } else {
            noTransitionLegacy();
        }
    }

    @SuppressWarnings("deprecation")
    private void noTransitionLegacy() {
        overridePendingTransition(0, 0);
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
