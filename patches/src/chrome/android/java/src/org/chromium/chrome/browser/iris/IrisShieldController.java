// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.core.widget.ImageViewCompat;

import org.chromium.base.ContextUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.ActivityTabProvider;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.theme.ThemeColorProvider;
import org.chromium.chrome.browser.theme.ThemeColorProvider.TintObserver;
import org.chromium.chrome.browser.ui.theme.BrandedColorScheme;
import org.chromium.components.browser_ui.styles.SemanticColorUtils;
import org.chromium.content_public.browser.WebContents;
import org.chromium.url.GURL;

/**
 * The shield button in the Android toolbar: the number of ads, trackers, cookies and
 * fingerprinting attempts blocked on the current page; tapping it opens {@link IrisShieldSheet}.
 * Added by {@code ToolbarManager} (apply-android-shield.sh): phones at the start of the button
 * row, tablets and unfolded foldables just before the optional button (see {@link #attach}).
 */
@NullMarked
public final class IrisShieldController implements TintObserver {
    /**
     * App preference: show the shield button (Settings > Appearance > Shield button), default on.
     * The shield's protections work either way; only the button is hidden.
     */
    public static final String SHOW_BUTTON_PREF = "iris_shield_button";

    private final Activity mActivity;
    private final ViewGroup mButtonRow;
    private final ThemeColorProvider mTintProvider;
    private final FrameLayout mButton;
    private final ImageView mIcon;
    private final TextView mBadge;
    private final ActivityTabProvider.ActivityTabTabObserver mTabObserver;
    // Kept as a field: SharedPreferences holds its listeners weakly.
    private final SharedPreferences.OnSharedPreferenceChangeListener mPrefListener =
            (prefs, key) -> {
                if (SHOW_BUTTON_PREF.equals(key)) updateButtonVisibility();
            };
    private @Nullable Tab mTab;
    private @Nullable IrisShield mShield;

    /**
     * Phone layout: first in the button row (R.id.toolbar_buttons). Tablet layout (tablets and
     * unfolded foldables, 600 dp and wider): the whole toolbar is one row
     * (R.id.toolbar_tablet_layout); the shield goes just before the optional (adaptive) button, the
     * same order as on phones. Returns null when neither row is found.
     */
    public static @Nullable IrisShieldController attach(
            Activity activity,
            View toolbarContainer,
            ActivityTabProvider tabProvider,
            ThemeColorProvider tintProvider) {
        View row = toolbarContainer.findViewById(R.id.toolbar_buttons);
        if (row instanceof ViewGroup) {
            return new IrisShieldController(
                    activity, (ViewGroup) row, 0, tabProvider, tintProvider);
        }
        View tabletRow = toolbarContainer.findViewById(R.id.toolbar_tablet_layout);
        if (!(tabletRow instanceof ViewGroup)) return null;
        ViewGroup tabletGroup = (ViewGroup) tabletRow;
        // The optional button is a ViewStub until first shown; once inflated it takes the stub's
        // place under another id. Fall back to the tab switcher if neither is a direct child.
        int[] anchors = {
            R.id.optional_button_stub, R.id.optional_toolbar_button, R.id.tab_switcher_button
        };
        for (int id : anchors) {
            View anchor = tabletGroup.findViewById(id);
            int index = anchor != null ? tabletGroup.indexOfChild(anchor) : -1;
            if (index >= 0) {
                return new IrisShieldController(
                        activity, tabletGroup, index, tabProvider, tintProvider);
            }
        }
        return null;
    }

    private IrisShieldController(
            Activity activity,
            ViewGroup buttonRow,
            int insertIndex,
            ActivityTabProvider tabProvider,
            ThemeColorProvider tintProvider) {
        mActivity = activity;
        mButtonRow = buttonRow;
        mTintProvider = tintProvider;

        mButton = new FrameLayout(activity);
        TypedValue ripple = new TypedValue();
        activity.getTheme()
                .resolveAttribute(
                        android.R.attr.selectableItemBackgroundBorderless, ripple, true);
        mButton.setBackgroundResource(ripple.resourceId);
        mButton.setClickable(true);
        mButton.setFocusable(true);
        mButton.setOnClickListener(v -> openSheet());

        mIcon = new ImageView(activity);
        mIcon.setImageResource(R.drawable.iris_ic_shield);
        mIcon.setScaleType(ImageView.ScaleType.CENTER);
        mButton.addView(
                mIcon,
                new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        mBadge = new TextView(activity);
        mBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9);
        mBadge.setTypeface(Typeface.DEFAULT_BOLD);
        mBadge.setGravity(Gravity.CENTER);
        mBadge.setIncludeFontPadding(false);
        mBadge.setMinWidth(dp(15));
        mBadge.setPadding(dp(3), dp(1), dp(3), dp(1));
        GradientDrawable pill = new GradientDrawable();
        pill.setCornerRadius(dp(8));
        pill.setColor(SemanticColorUtils.getColorPrimary(activity));
        mBadge.setBackground(pill);
        mBadge.setTextColor(SemanticColorUtils.getColorOnPrimary(activity));
        FrameLayout.LayoutParams badgeParams =
                new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        Gravity.TOP | Gravity.END);
        badgeParams.topMargin = dp(9);
        badgeParams.setMarginEnd(dp(4));
        mButton.addView(mBadge, badgeParams);
        mBadge.setVisibility(View.GONE);

        mButtonRow.addView(
                mButton,
                insertIndex,
                new ViewGroup.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT));
        updateButtonVisibility();
        ContextUtils.getAppSharedPreferences().registerOnSharedPreferenceChangeListener(mPrefListener);

        mTintProvider.addTintObserver(this);
        onTintChanged(
                mTintProvider.getTint(), mTintProvider.getTint(), BrandedColorScheme.APP_DEFAULT);

        mTabObserver =
                new ActivityTabProvider.ActivityTabTabObserver(tabProvider, true) {
                    @Override
                    protected void onObservingDifferentTab(@Nullable Tab tab) {
                        bind(tab);
                    }

                    @Override
                    public void onContentChanged(Tab tab) {
                        bind(tab);
                    }

                    @Override
                    public void onUrlUpdated(Tab tab) {
                        update();
                    }

                    @Override
                    public void onPageLoadFinished(Tab tab, GURL url) {
                        update();
                    }
                };
    }

    public void destroy() {
        ContextUtils.getAppSharedPreferences()
                .unregisterOnSharedPreferenceChangeListener(mPrefListener);
        mTabObserver.destroy();
        mTintProvider.removeTintObserver(this);
        unbind();
        mButtonRow.removeView(mButton);
    }

    @Override
    public void onTintChanged(
            @Nullable ColorStateList tint,
            @Nullable ColorStateList activityFocusTint,
            @BrandedColorScheme int brandedColorScheme) {
        ImageViewCompat.setImageTintList(mIcon, activityFocusTint != null ? activityFocusTint : tint);
    }

    private void updateButtonVisibility() {
        mButton.setVisibility(
                ContextUtils.getAppSharedPreferences().getBoolean(SHOW_BUTTON_PREF, true)
                        ? View.VISIBLE
                        : View.GONE);
    }

    private void bind(@Nullable Tab tab) {
        unbind();
        mTab = tab;
        WebContents webContents = tab != null ? tab.getWebContents() : null;
        if (webContents != null) {
            mShield = new IrisShield(webContents, this::update);
        }
        update();
    }

    private void unbind() {
        if (mShield != null) {
            mShield.destroy();
            mShield = null;
        }
        mTab = null;
    }

    private void update() {
        WebContents webContents = mTab != null ? mTab.getWebContents() : null;
        int total = IrisShield.getCounts(webContents)[IrisShield.TOTAL];
        mBadge.setText(total > 99 ? "99+" : String.valueOf(total));
        mBadge.setVisibility(total > 0 ? View.VISIBLE : View.GONE);
        mButton.setContentDescription(
                total == 1
                        ? "Shield: 1 item blocked on this page"
                        : "Shield: " + total + " items blocked on this page");
    }

    private void openSheet() {
        if (mTab == null) return;
        IrisShieldSheet.show(mActivity, mTab, this::update);
    }

    private int dp(int value) {
        return Math.round(value * mActivity.getResources().getDisplayMetrics().density);
    }
}
