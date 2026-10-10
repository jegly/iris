// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.core.widget.ImageViewCompat;

import com.google.android.material.materialswitch.MaterialSwitch;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.privacy.settings.PrivacySettings;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.settings.SettingsNavigationFactory;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.components.browser_ui.styles.SemanticColorUtils;
import org.chromium.content_public.browser.WebContents;
import org.chromium.url.GURL;

import java.util.ArrayList;
import java.util.List;

/**
 * The shield sheet on Android: the same content as the desktop shield panel, in a sheet at the
 * bottom of the screen. Counts for the page, every Iris setting for the site, the connection
 * details. Changes reload the tab (except "Forget this site").
 */
@NullMarked
final class IrisShieldSheet {
    // Same order as the desktop panel (iris_toolbar_buttons.cc kIdentities).
    private static final String[] IDENTITY_IDS = {
        "", "firefox_linux", "firefox_windows", "firefox_mac", "firefox_android",
        "chrome_windows", "chrome_mac", "chrome_linux", "chrome_android", "chrome_ios",
        "edge_windows", "safari_mac", "safari_ios", "samsung_android"
    };
    private static final String[] IDENTITY_NAMES = {
        "Iris default", "Firefox, Linux", "Firefox, Windows", "Firefox, macOS",
        "Firefox, Android", "Chrome, Windows", "Chrome, macOS", "Chrome, Linux",
        "Chrome, Android", "Chrome, iPhone", "Edge, Windows", "Safari, macOS", "Safari, iPhone",
        "Samsung Internet"
    };
    private static final String[] CANVAS_IDS = {"protected", "real", "blank"};
    private static final String[] CANVAS_NAMES = {"Protected", "Real", "Blank"};

    private final Activity mActivity;
    private final Tab mTab;
    private final Profile mProfile;
    private final String mUrl;
    private final boolean mWeb;
    private final Dialog mDialog;
    private final LinearLayout mBody;
    private final List<Runnable> mSyncers = new ArrayList<>();
    private @Nullable IrisShield mShield;
    private @Nullable TextView mTotal;
    private @Nullable TextView mBreakdown;
    private @Nullable TextView mLifetime;
    private @Nullable TextView mStatus;
    private boolean mSyncing;

    static void show(Activity activity, Tab tab, Runnable onClosed) {
        new IrisShieldSheet(activity, tab, onClosed);
    }

    private IrisShieldSheet(Activity activity, Tab tab, Runnable onClosed) {
        mActivity = activity;
        mTab = tab;
        mProfile = tab.getProfile();
        GURL url = tab.getUrl();
        mUrl = url.getSpec();
        mWeb = url.getScheme().equals("http") || url.getScheme().equals("https");

        mBody = new LinearLayout(activity);
        mBody.setOrientation(LinearLayout.VERTICAL);
        mBody.setPadding(dp(20), dp(16), dp(20), dp(20));

        buildHeader(url);
        buildCounts();
        buildSiteControls();
        buildConnection();
        buildFooter();

        ScrollView scroll =
                new ScrollView(activity) {
                    @Override
                    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
                        // Never taller than 85 % of the screen; the rest scrolls.
                        int max =
                                (int) (getResources().getDisplayMetrics().heightPixels * 0.85f);
                        super.onMeasure(
                                widthMeasureSpec,
                                MeasureSpec.makeMeasureSpec(max, MeasureSpec.AT_MOST));
                    }
                };
        scroll.addView(mBody);
        GradientDrawable background = new GradientDrawable();
        float r = dp(20);
        background.setCornerRadii(new float[] {r, r, r, r, 0, 0, 0, 0});
        background.setColor(SemanticColorUtils.getColorSurfaceContainer(activity));
        scroll.setBackground(background);

        mDialog = new Dialog(activity);
        mDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        mDialog.setContentView(scroll);
        Window window = mDialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(0));
            window.setGravity(Gravity.BOTTOM);
            window.setLayout(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT);
        }
        WebContents webContents = tab.getWebContents();
        if (webContents != null) {
            mShield = new IrisShield(webContents, this::updateCounts);
        }
        mDialog.setOnDismissListener(
                d -> {
                    if (mShield != null) {
                        mShield.destroy();
                        mShield = null;
                    }
                    onClosed.run();
                });
        updateCounts();
        sync();
        mDialog.show();
    }

    // --- building ---------------------------------------------------------------------------

    private void buildHeader(GURL url) {
        LinearLayout header = row();
        ImageView icon = new ImageView(mActivity);
        icon.setImageResource(R.drawable.iris_ic_shield);
        ImageViewCompat.setImageTintList(
                icon, ColorStateList.valueOf(SemanticColorUtils.getColorPrimary(mActivity)));
        header.addView(icon, new LinearLayout.LayoutParams(dp(28), dp(28)));

        LinearLayout column = new LinearLayout(mActivity);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(dp(12), 0, dp(8), 0);
        TextView host = text(mWeb ? url.getHost() : "This page", 17, true);
        column.addView(host);
        mStatus = secondary("");
        column.addView(mStatus);
        header.addView(column, weighted());

        MaterialSwitch master = new MaterialSwitch(mActivity);
        master.setContentDescription("Shield for this site");
        master.setEnabled(mWeb);
        master.setOnCheckedChangeListener(
                (b, on) -> {
                    if (mSyncing) return;
                    IrisShield.setShield(mProfile, mUrl, on);
                    changed(true);
                });
        mSyncers.add(() -> master.setChecked(mWeb && isOn(IrisShield.ADS)));
        header.addView(master);
        mBody.addView(header);
    }

    private void buildCounts() {
        LinearLayout card = row();
        card.setPadding(dp(16), dp(12), dp(16), dp(12));
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(14));
        bg.setColor(SemanticColorUtils.getColorPrimaryContainer(mActivity));
        card.setBackground(bg);
        mTotal = text("0", 30, true);
        card.addView(mTotal);
        LinearLayout column = new LinearLayout(mActivity);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(dp(14), 0, 0, 0);
        column.addView(text("blocked on this page", 14, false));
        mBreakdown = secondary("");
        column.addView(mBreakdown);
        card.addView(column, weighted());
        LinearLayout.LayoutParams params = matchWidth();
        params.topMargin = dp(14);
        mBody.addView(card, params);
        mLifetime = secondary("");
        mLifetime.setPadding(0, dp(6), 0, 0);
        mBody.addView(mLifetime);
    }

    private void buildSiteControls() {
        section("This site");
        switchRow("Block ads and trackers", IrisShield.ADS);
        switchRow("Block cross-site cookies", IrisShield.COOKIES);
        switchRow("JavaScript", IrisShield.JAVASCRIPT);
        switchRow("JavaScript optimisation (faster, less secure)", IrisShield.JIT);
        switchRow("WebGL (3D graphics)", IrisShield.WEBGL);
        switchRow("Google sign-in prompts", IrisShield.SIGN_IN);
        switchRow("Forget this site when I close Iris", IrisShield.FORGET);
        listRow(
                "Canvas and audio",
                CANVAS_NAMES,
                () -> indexOf(CANVAS_IDS, IrisSiteSettings.getFingerprintReadsPreset(mProfile, mUrl)),
                i -> IrisSiteSettings.setFingerprintReadsPreset(mProfile, mUrl, CANVAS_IDS[i]));
        listRow(
                "Browser identity",
                IDENTITY_NAMES,
                () -> indexOf(IDENTITY_IDS, IrisSiteSettings.getUserAgentPreset(mProfile, mUrl)),
                i -> IrisSiteSettings.setUserAgentPreset(mProfile, mUrl, IDENTITY_IDS[i]));
    }

    private void buildConnection() {
        section("Connection");
        String details = IrisShield.getConnectionDetails(mTab.getWebContents());
        if (details.trim().isEmpty()) {
            mBody.addView(secondary(mWeb ? "Not encrypted" : "No connection details"));
            return;
        }
        // Every line, always visible (no "Details" button), as on desktop.
        for (String line : details.split("\n")) {
            if (!line.trim().isEmpty()) mBody.addView(secondary(line.trim()));
        }
    }

    private void buildFooter() {
        LinearLayout footer = row();
        footer.setPadding(0, dp(12), 0, 0);
        Button reset = new Button(mActivity, null, android.R.attr.borderlessButtonStyle);
        reset.setText("Reset this site");
        reset.setAllCaps(false);
        reset.setTextColor(SemanticColorUtils.getColorPrimary(mActivity));
        reset.setEnabled(mWeb);
        reset.setOnClickListener(
                v -> {
                    IrisShield.reset(mProfile, mUrl);
                    changed(true);
                });
        footer.addView(reset);
        footer.addView(new View(mActivity), weighted());
        ImageButton gear = new ImageButton(mActivity);
        gear.setImageResource(R.drawable.ic_settings_24dp);
        ImageViewCompat.setImageTintList(
                gear, ColorStateList.valueOf(SemanticColorUtils.getDefaultIconColor(mActivity)));
        TypedValue ripple = new TypedValue();
        mActivity
                .getTheme()
                .resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, ripple, true);
        gear.setBackgroundResource(ripple.resourceId);
        gear.setContentDescription("Iris hardening settings");
        gear.setOnClickListener(
                v -> {
                    mDialog.dismiss();
                    SettingsNavigationFactory.createSettingsNavigation()
                            .startSettings(mActivity, PrivacySettings.class);
                });
        footer.addView(gear, new LinearLayout.LayoutParams(dp(48), dp(48)));
        mBody.addView(footer);
    }

    private void switchRow(String label, int which) {
        LinearLayout line = row();
        line.setPadding(0, dp(4), 0, dp(4));
        TextView name = text(label, 15, false);
        line.addView(name, weighted());
        MaterialSwitch toggle = new MaterialSwitch(mActivity);
        toggle.setContentDescription(label);
        toggle.setOnCheckedChangeListener(
                (b, on) -> {
                    if (mSyncing) return;
                    IrisShield.set(mProfile, mUrl, which, on);
                    changed(which != IrisShield.FORGET);
                });
        mSyncers.add(
                () -> {
                    boolean locked = IrisShield.isLocked(mProfile, which);
                    toggle.setEnabled(mWeb && !locked);
                    toggle.setChecked(mWeb && IrisShield.isOn(mProfile, mUrl, which));
                    name.setAlpha(mWeb && !locked ? 1f : 0.5f);
                });
        line.addView(toggle);
        mBody.addView(line);
    }

    private interface IndexGetter {
        int get();
    }

    private interface IndexSetter {
        void set(int index);
    }

    private void listRow(String label, String[] names, IndexGetter getter, IndexSetter setter) {
        LinearLayout line = row();
        line.setPadding(0, dp(4), 0, dp(4));
        line.addView(text(label, 15, false), weighted());
        Spinner spinner = new Spinner(mActivity);
        ArrayAdapter<String> adapter =
                new ArrayAdapter<>(mActivity, android.R.layout.simple_spinner_item, names);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
        spinner.setContentDescription(label);
        spinner.setEnabled(mWeb);
        spinner.setOnItemSelectedListener(
                new AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(
                            AdapterView<?> parent, View view, int position, long id) {
                        if (mSyncing || position == getter.get()) return;
                        setter.set(position);
                        changed(true);
                    }

                    @Override
                    public void onNothingSelected(AdapterView<?> parent) {}
                });
        mSyncers.add(() -> spinner.setSelection(mWeb ? getter.get() : 0, false));
        line.addView(spinner);
        mBody.addView(line);
    }

    // --- state ------------------------------------------------------------------------------

    private boolean isOn(int which) {
        return IrisShield.isOn(mProfile, mUrl, which);
    }

    private void sync() {
        mSyncing = true;
        for (Runnable syncer : mSyncers) syncer.run();
        mSyncing = false;
        if (mStatus != null) {
            mStatus.setText(
                    !mWeb
                            ? "Not used on this page"
                            : isOn(IrisShield.ADS) ? "Shield is on" : "Shield is off for this site");
        }
    }

    private void changed(boolean reload) {
        sync();
        if (reload) mTab.reload();
    }

    private void updateCounts() {
        int[] c = IrisShield.getCounts(mTab.getWebContents());
        if (mTotal != null) mTotal.setText(String.valueOf(c[IrisShield.TOTAL]));
        if (mBreakdown != null) {
            mBreakdown.setText(
                    c[IrisShield.ADS_AND_TRACKERS]
                            + " ads, trackers · "
                            + c[IrisShield.COOKIE_COUNT]
                            + " cookies · "
                            + c[IrisShield.FINGERPRINTS]
                            + " fingerprints");
        }
        if (mLifetime != null) {
            mLifetime.setText(
                    c[IrisShield.LIFETIME] + " blocked since you started using Iris");
        }
    }

    // --- small helpers ----------------------------------------------------------------------

    private static int indexOf(String[] ids, String id) {
        for (int i = 0; i < ids.length; i++) {
            if (ids[i].equals(id)) return i;
        }
        return 0;
    }

    private void section(String title) {
        View divider = new View(mActivity);
        divider.setBackgroundColor(SemanticColorUtils.getDividerColor(mActivity));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Math.max(1, dp(1) / 2));
        params.topMargin = dp(14);
        params.bottomMargin = dp(10);
        mBody.addView(divider, params);
        mBody.addView(text(title, 14, true));
    }

    private LinearLayout row() {
        LinearLayout row = new LinearLayout(mActivity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }

    private TextView text(String value, int sp, boolean bold) {
        TextView view = new TextView(mActivity);
        view.setText(value);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        view.setTextColor(SemanticColorUtils.getDefaultTextColor(mActivity));
        if (bold) view.setTypeface(Typeface.DEFAULT_BOLD);
        return view;
    }

    private TextView secondary(String value) {
        TextView view = text(value, 13, false);
        view.setTextColor(SemanticColorUtils.getDefaultTextColorSecondary(mActivity));
        return view;
    }

    private static LinearLayout.LayoutParams weighted() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
    }

    private static LinearLayout.LayoutParams matchWidth() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        Context context = mActivity;
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }
}
