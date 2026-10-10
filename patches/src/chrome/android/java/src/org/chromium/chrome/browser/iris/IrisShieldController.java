// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

package org.chromium.chrome.browser.iris;

import android.app.Activity;
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
 * The shield button in the Android toolbar (phone layout): the number of ads, trackers, cookies
 * and fingerprinting attempts blocked on the current page; tapping it opens {@link
 * IrisShieldSheet}. Added at the start of the toolbar's button row by {@code ToolbarManager}
 * (apply-android-shield.sh). Tablets use another toolbar layout and get no button yet.
 */
@NullMarked
public final class IrisShieldController implements TintObserver {
    private final Activity mActivity;
    private final ViewGroup mButtonRow;
    private final ThemeColorProvider mTintProvider;
    private final FrameLayout mButton;
    private final ImageView mIcon;
    private final TextView mBadge;
    private final ActivityTabProvider.ActivityTabTabObserver mTabObserver;
    private @Nullable Tab mTab;
    private @Nullable IrisShield mShield;

    /** Returns null when the toolbar has no button row (tablet layout). */
    public static @Nullable IrisShieldController attach(
            Activity activity,
            View toolbarContainer,
            ActivityTabProvider tabProvider,
            ThemeColorProvider tintProvider) {
        View row = toolbarContainer.findViewById(R.id.toolbar_buttons);
        if (!(row instanceof ViewGroup)) return null;
        return new IrisShieldController(activity, (ViewGroup) row, tabProvider, tintProvider);
    }

    private IrisShieldController(
            Activity activity,
            ViewGroup buttonRow,
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
                mButton, 0, new ViewGroup.LayoutParams(dp(48), ViewGroup.LayoutParams.MATCH_PARENT));

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
