// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.text.InputType;
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
import org.chromium.chrome.browser.init.ChromeBrowserInitializer;

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

        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER);
        layout.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Iris is locked");
        title.setTextSize(24);
        title.setGravity(Gravity.CENTER);
        layout.addView(title);

        EditText passphrase = new EditText(this);
        passphrase.setHint("Passphrase");
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
        unlock.setOnClickListener(v -> unlockWithPassphrase());
        layout.addView(unlock);
        mUnlock = unlock;

        Button fingerprint = new Button(this);
        fingerprint.setText("Use fingerprint");
        fingerprint.setVisibility(View.GONE);
        fingerprint.setOnClickListener(v -> unlockWithFingerprint());
        layout.addView(fingerprint);
        mFingerprint = fingerprint;

        TextView message = new TextView(this);
        message.setGravity(Gravity.CENTER);
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
