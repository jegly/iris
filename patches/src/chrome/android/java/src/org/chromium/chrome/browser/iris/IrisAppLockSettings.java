// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Build;
import android.os.CancellationSignal;
import android.text.InputType;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;

import org.chromium.build.annotations.NullMarked;

import java.util.function.Consumer;

import javax.crypto.Cipher;

/** Settings > Privacy and security > Iris > "Lock Iris": set, change, fingerprint, turn off. */
@NullMarked
public final class IrisAppLockSettings {
    private IrisAppLockSettings() {}

    public static String summary() {
        if (!IrisAppLock.isLockSet()) return "Off";
        return IrisAppLock.isBiometricSet() ? "On, fingerprint allowed" : "On";
    }

    /** Opens the right dialog; {@code onChanged} refreshes the summary. */
    public static void show(Activity activity, Runnable onChanged) {
        if (!IrisAppLock.isLockSet()) {
            askNew(activity, "", onChanged);
            return;
        }
        String fingerprint =
                IrisAppLock.isBiometricSet()
                        ? "Turn off fingerprint unlock"
                        : "Unlock with fingerprint";
        new AlertDialog.Builder(activity)
                .setTitle("Lock Iris")
                .setItems(
                        new String[] {"Change passphrase", fingerprint, "Turn off the lock"},
                        (dialog, which) -> {
                            if (which == 0) {
                                askOne(
                                        activity,
                                        "Current passphrase",
                                        current -> askNew(activity, current, onChanged));
                            } else if (which == 1) {
                                if (IrisAppLock.isBiometricSet()) {
                                    IrisAppLock.clearBiometric();
                                    onChanged.run();
                                } else {
                                    askOne(
                                            activity,
                                            "Passphrase",
                                            current ->
                                                    enrollFingerprint(
                                                            activity, current, onChanged));
                                }
                            } else {
                                askOne(
                                        activity,
                                        "Passphrase",
                                        current -> {
                                            int result = IrisAppLock.remove(current);
                                            toast(
                                                    activity,
                                                    result == IrisAppLock.RESULT_OK
                                                            ? "The lock is off"
                                                            : "Wrong passphrase");
                                            onChanged.run();
                                        });
                            }
                        })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    private static EditText passwordField(Activity activity, String hint) {
        EditText field = new EditText(activity);
        field.setHint(hint);
        field.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        return field;
    }

    private static LinearLayout column(Activity activity) {
        int pad = (int) (20 * activity.getResources().getDisplayMetrics().density);
        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(pad, pad / 2, pad, 0);
        return layout;
    }

    private static void askOne(Activity activity, String hint, Consumer<String> onEntered) {
        LinearLayout layout = column(activity);
        EditText field = passwordField(activity, hint);
        layout.addView(field);
        new AlertDialog.Builder(activity)
                .setTitle("Lock Iris")
                .setView(layout)
                .setPositiveButton(
                        android.R.string.ok,
                        (dialog, which) -> onEntered.accept(field.getText().toString()))
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    // `current` is "" when the lock is off.
    private static void askNew(Activity activity, String current, Runnable onChanged) {
        LinearLayout layout = column(activity);
        TextView warning = new TextView(activity);
        warning.setText(
                "Iris will ask for this passphrase when it opens and after 5 minutes in the"
                        + " background. It also encrypts your cookies, bookmarks and open tabs."
                        + " There is no recovery: if you forget it, that data is lost.");
        layout.addView(warning);
        EditText first = passwordField(activity, "New passphrase");
        EditText second = passwordField(activity, "Repeat passphrase");
        layout.addView(first);
        layout.addView(second);
        new AlertDialog.Builder(activity)
                .setTitle(current.isEmpty() ? "Lock Iris" : "Change passphrase")
                .setView(layout)
                .setPositiveButton(
                        android.R.string.ok,
                        (dialog, which) -> {
                            String passphrase = first.getText().toString();
                            if (!passphrase.equals(second.getText().toString())) {
                                toast(activity, "The passphrases don't match");
                                return;
                            }
                            int result = IrisAppLock.setPassphrase(current, passphrase);
                            if (result == IrisAppLock.RESULT_EMPTY_PASSPHRASE) {
                                toast(activity, "Enter a passphrase");
                            } else if (result == IrisAppLock.RESULT_WRONG_PASSPHRASE) {
                                toast(activity, "Wrong current passphrase");
                            } else {
                                toast(activity, "Iris is locked with your passphrase");
                                onChanged.run();
                                if (hasStrongBiometric(activity)) {
                                    new AlertDialog.Builder(activity)
                                            .setTitle("Unlock with fingerprint too?")
                                            .setPositiveButton(
                                                    android.R.string.ok,
                                                    (d, w) ->
                                                            enrollFingerprint(
                                                                    activity,
                                                                    passphrase,
                                                                    onChanged))
                                            .setNegativeButton(android.R.string.cancel, null)
                                            .show();
                                }
                            }
                        })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    private static boolean hasStrongBiometric(Activity activity) {
        BiometricManager manager = activity.getSystemService(BiometricManager.class);
        if (manager == null) return false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    == BiometricManager.BIOMETRIC_SUCCESS;
        }
        @SuppressWarnings("deprecation")
        int result = manager.canAuthenticate();
        return result == BiometricManager.BIOMETRIC_SUCCESS;
    }

    private static void enrollFingerprint(Activity activity, String passphrase, Runnable onChanged) {
        if (!IrisAppLock.unlock(passphrase)) {
            toast(activity, "Wrong passphrase");
            return;
        }
        if (!hasStrongBiometric(activity)) {
            toast(activity, "No fingerprint is set up on this phone");
            return;
        }
        Cipher cipher = IrisAppLock.encryptCipher();
        if (cipher == null) {
            toast(activity, "Fingerprint unlock is not available on this phone");
            return;
        }
        BiometricPrompt.Builder builder =
                new BiometricPrompt.Builder(activity)
                        .setTitle("Unlock Iris with fingerprint")
                        .setNegativeButton(
                                activity.getString(android.R.string.cancel),
                                activity.getMainExecutor(),
                                (d, w) -> {});
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG);
        }
        builder.build()
                .authenticate(
                        new BiometricPrompt.CryptoObject(cipher),
                        new CancellationSignal(),
                        activity.getMainExecutor(),
                        new BiometricPrompt.AuthenticationCallback() {
                            @Override
                            public void onAuthenticationSucceeded(
                                    BiometricPrompt.AuthenticationResult result) {
                                BiometricPrompt.CryptoObject crypto = result.getCryptoObject();
                                Cipher authenticated = crypto == null ? null : crypto.getCipher();
                                boolean ok =
                                        authenticated != null
                                                && IrisAppLock.storeBiometric(
                                                        authenticated, passphrase);
                                toast(
                                        activity,
                                        ok
                                                ? "Fingerprint unlock is on"
                                                : "Could not turn on fingerprint unlock");
                                onChanged.run();
                            }
                        });
    }

    private static void toast(Activity activity, String text) {
        Toast.makeText(activity, text, Toast.LENGTH_LONG).show();
    }
}
