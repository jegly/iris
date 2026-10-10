// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

/**
 * @fileoverview
 * 'settings-iris-theme-editor-page': Settings > Appearance > Theme editor
 * (patches/apply-theme-editor.sh). Colours for each part of the window
 * (pref iris.theme.custom, applied by chrome/browser/ui/color/iris_theme_mixer),
 * saved themes, theme codes to share, and "Recolour websites"
 * (iris.web_recolor.*, chrome/browser/iris/iris_web_recolor).
 */

import '../controls/settings_toggle_button.js';
import '../settings_page/settings_subpage.js';
import 'chrome://resources/cr_elements/cr_button/cr_button.js';
import 'chrome://resources/cr_elements/cr_input/cr_input.js';

import {PrefService} from '/shared/settings/prefs2/pref_service.js';
import {PrefServiceObserverMixinLit} from '/shared/settings/prefs2/pref_service_observer_mixin_lit.js';
import {getCss as getCrSharedStyleLit} from 'chrome://resources/cr_elements/cr_shared_style_lit.css.js';
import {CrLitElement, css} from 'chrome://resources/lit/v3_0/lit.rollup.js';
import type {CSSResultGroup} from 'chrome://resources/lit/v3_0/lit.rollup.js';

import {SettingsViewMixinLit} from '../settings_page/settings_view_mixin_lit.js';
import {getCss as getSettingsSharedLit} from '../settings_shared_lit.css.js';

import {getHtml} from './iris_theme_editor_page.html.js';

type PrefObject<T> = chrome.settingsPrivate.PrefObject<T>;

export const CUSTOM_COLORS_PREF = 'iris.theme.custom';
export const SAVED_THEMES_PREF = 'iris.theme.saved';
const CODE_PREFIX = 'IRIS-THEME-1:';

export interface ThemeItem {
  key: string;
  label: string;
  // CSS variable used to show the palette's colour while the item is not set.
  fallbackVar: string;
}

export interface ThemeGroup {
  title: string;
  items: ThemeItem[];
}

export interface SavedTheme {
  name: string;
  colors: Record<string, string>;
}

// Keys must match chrome/browser/ui/color/iris_theme_mixer.h.
export const THEME_GROUPS: ThemeGroup[] = [
  {
    title: 'Whole browser',
    items: [
      {key: 'accent', label: 'Accent (switches, buttons, highlights, links)',
       fallbackVar: '--color-sys-primary'},
      {key: 'text', label: 'Text', fallbackVar: '--color-sys-on-surface'},
      {key: 'text2', label: 'Secondary text',
       fallbackVar: '--color-sys-on-surface-subtle'},
      {key: 'background', label: 'Background', fallbackVar: '--color-sys-base'},
      {key: 'surface', label: 'Menus, dialogs and cards',
       fallbackVar: '--color-sys-surface'},
    ],
  },
  {
    title: 'Title bar and tabs',
    items: [
      {key: 'titlebar', label: 'Title bar', fallbackVar: '--color-sys-header'},
      {key: 'titlebar_inactive', label: 'Title bar, window not focused',
       fallbackVar: '--color-sys-header-inactive'},
      {key: 'tab', label: 'Selected tab',
       fallbackVar: '--color-sys-base-container-elevated'},
      {key: 'tab_text', label: 'Selected tab text',
       fallbackVar: '--color-sys-on-surface'},
      {key: 'tab_text_inactive', label: 'Other tabs’ text',
       fallbackVar: '--color-sys-on-surface-subtle'},
    ],
  },
  {
    title: 'Toolbar',
    items: [
      {key: 'toolbar', label: 'Toolbar', fallbackVar: '--color-sys-base'},
      {key: 'toolbar_icons', label: 'Toolbar icons',
       fallbackVar: '--color-sys-on-surface-subtle'},
      {key: 'bookmarks_text', label: 'Bookmarks bar text',
       fallbackVar: '--color-sys-on-surface'},
    ],
  },
  {
    title: 'Address bar',
    items: [
      {key: 'omnibox', label: 'Address bar',
       fallbackVar: '--color-sys-omnibox-container'},
      {key: 'omnibox_text', label: 'Address bar text',
       fallbackVar: '--color-sys-on-surface'},
      {key: 'suggestions', label: 'Suggestions list',
       fallbackVar: '--color-sys-base'},
    ],
  },
  {
    title: 'Pages and panels',
    items: [
      {key: 'ntp', label: 'New tab page background',
       fallbackVar: '--color-sys-base'},
      {key: 'side_panel', label: 'Side panel', fallbackVar: '--color-sys-base'},
    ],
  },
];

const KNOWN_KEYS = new Set(THEME_GROUPS.flatMap(g => g.items.map(i => i.key)));
const HEX = /^#[0-9a-f]{6}$/;

const SettingsIrisThemeEditorPageElementBase =
    SettingsViewMixinLit(PrefServiceObserverMixinLit(CrLitElement));

export class SettingsIrisThemeEditorPageElement extends
    SettingsIrisThemeEditorPageElementBase {
  static get is() {
    return 'settings-iris-theme-editor-page';
  }

  static override get styles(): CSSResultGroup {
    return [getCrSharedStyleLit(), getSettingsSharedLit(), css`
      .group-title { font-weight: 500; padding-top: 16px; }
      .swatch-row { display: flex; align-items: center; gap: 12px; }
      .swatch-row .label { flex: 1; }
      .from-palette { color: var(--cr-secondary-text-color); font-size: 12px; }
      input[type=color] {
        width: 44px; height: 28px; padding: 0; border: 1px solid
        var(--cr-separator-color); border-radius: 6px; background: none;
        cursor: pointer;
      }
      .code-row { display: flex; gap: 8px; align-items: center; }
      .code-row cr-input { flex: 1; }
      .note { color: var(--cr-secondary-text-color); font-size: 12px; }
      .error { color: var(--cr-input-error-color, var(--color-sys-error)); }
    `];
  }

  override render() {
    return getHtml.bind(this)();
  }

  static override get properties() {
    return {
      customColorsPref_: {type: Object},
      savedThemesPref_: {type: Object},
      recolorEnabledPref_: {type: Object},
      recolorBrightnessPref_: {type: Object},
      recolorContrastPref_: {type: Object},
      themeName_: {type: String},
      themeCode_: {type: String},
      message_: {type: String},
      messageIsError_: {type: Boolean},
    };
  }

  protected accessor customColorsPref_:
      PrefObject<Record<string, string>>|undefined = undefined;
  protected accessor savedThemesPref_: PrefObject<SavedTheme[]>|undefined =
      undefined;
  protected accessor recolorEnabledPref_: PrefObject<boolean>|undefined =
      undefined;
  protected accessor recolorBrightnessPref_: PrefObject<number>|undefined =
      undefined;
  protected accessor recolorContrastPref_: PrefObject<number>|undefined =
      undefined;
  protected accessor themeName_: string = '';
  protected accessor themeCode_: string = '';
  protected accessor message_: string = '';
  protected accessor messageIsError_: boolean = false;
  protected readonly groups_: ThemeGroup[] = THEME_GROUPS;

  override connectedCallback() {
    super.connectedCallback();
    this.mirrorPrefs({
      [CUSTOM_COLORS_PREF]: 'customColorsPref_',
      [SAVED_THEMES_PREF]: 'savedThemesPref_',
      'iris.web_recolor.enabled': 'recolorEnabledPref_',
      'iris.web_recolor.brightness': 'recolorBrightnessPref_',
      'iris.web_recolor.contrast': 'recolorContrastPref_',
    });
  }

  // SettingsViewMixin implementation.
  override focusBackButton() {
    this.shadowRoot.querySelector('settings-subpage')!.focusBackButton();
  }

  // --- colours --------------------------------------------------------------

  protected colors_(): Record<string, string> {
    return {...(this.customColorsPref_?.value || {})};
  }

  protected isSet_(key: string): boolean {
    return HEX.test(this.colors_()[key] || '');
  }

  // The colour shown in the swatch: the one set, else the palette's.
  protected swatchValue_(item: ThemeItem): string {
    const set = this.colors_()[item.key];
    if (set && HEX.test(set)) {
      return set;
    }
    return toHex(getComputedStyle(this).getPropertyValue(item.fallbackVar));
  }

  protected onColorChange_(e: Event) {
    const input = e.target as HTMLInputElement;
    const key = input.dataset['key'];
    if (!key || !HEX.test(input.value)) {
      return;
    }
    this.setColors_({...this.colors_(), [key]: input.value});
  }

  protected onResetItemClick_(e: Event) {
    const key = (e.currentTarget as HTMLElement).dataset['key'];
    if (!key) {
      return;
    }
    const colors = this.colors_();
    delete colors[key];
    this.setColors_(colors);
  }

  protected onResetAllClick_() {
    this.setColors_({});
    this.showMessage_('All colours are back to the palette.', false);
  }

  private setColors_(colors: Record<string, string>) {
    PrefService.getInstance().setPrefValue(CUSTOM_COLORS_PREF, colors);
  }

  // --- saved themes ---------------------------------------------------------

  protected savedThemes_(): SavedTheme[] {
    return [...(this.savedThemesPref_?.value || [])];
  }

  protected onThemeNameInput_(e: Event) {
    this.themeName_ = (e.target as HTMLInputElement).value;
  }

  protected onSaveThemeClick_() {
    const name = this.themeName_.trim();
    if (!name) {
      this.showMessage_('Give the theme a name first.', true);
      return;
    }
    const themes = this.savedThemes_().filter(t => t.name !== name);
    themes.push({name, colors: this.colors_()});
    PrefService.getInstance().setPrefValue(SAVED_THEMES_PREF, themes);
    this.themeName_ = '';
    this.showMessage_(`Saved “${name}”.`, false);
  }

  protected onApplyThemeClick_(e: Event) {
    const index = Number((e.currentTarget as HTMLElement).dataset['index']);
    const theme = this.savedThemes_()[index];
    if (theme) {
      this.setColors_(cleanColors(theme.colors) || {});
      this.showMessage_(`Using “${theme.name}”.`, false);
    }
  }

  protected onDeleteThemeClick_(e: Event) {
    const index = Number((e.currentTarget as HTMLElement).dataset['index']);
    const themes = this.savedThemes_();
    themes.splice(index, 1);
    PrefService.getInstance().setPrefValue(SAVED_THEMES_PREF, themes);
  }

  // --- theme codes ----------------------------------------------------------

  protected onExportClick_() {
    this.themeCode_ =
        CODE_PREFIX + btoa(JSON.stringify(this.colors_()));
    navigator.clipboard.writeText(this.themeCode_).then(
        () => this.showMessage_('Theme code copied.', false),
        () => this.showMessage_('Theme code is in the box below.', false));
  }

  protected onThemeCodeInput_(e: Event) {
    this.themeCode_ = (e.target as HTMLInputElement).value;
  }

  protected onImportClick_() {
    const code = this.themeCode_.trim();
    let colors: Record<string, string>|null = null;
    if (code.startsWith(CODE_PREFIX)) {
      try {
        colors = cleanColors(JSON.parse(atob(code.slice(CODE_PREFIX.length))));
      } catch {
        colors = null;
      }
    }
    if (!colors) {
      this.showMessage_('That is not an Iris theme code.', true);
      return;
    }
    this.setColors_(colors);
    this.showMessage_('Theme code applied.', false);
  }

  private showMessage_(text: string, isError: boolean) {
    this.message_ = text;
    this.messageIsError_ = isError;
  }

  // --- websites -------------------------------------------------------------

  protected onRecolorSliderChange_(e: Event) {
    const input = e.target as HTMLInputElement;
    const pref = input.dataset['pref'];
    if (pref) {
      PrefService.getInstance().setPrefValue(pref, Number(input.value));
    }
  }
}

// Keeps only known keys with "#rrggbb" values; null if `value` is not an
// object.
function cleanColors(value: unknown): Record<string, string>|null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const colors: Record<string, string> = {};
  for (const [key, color] of Object.entries(value as Record<string, unknown>)) {
    if (KNOWN_KEYS.has(key) && typeof color === 'string' &&
        HEX.test(color.toLowerCase())) {
      colors[key] = color.toLowerCase();
    }
  }
  return colors;
}

// "rgb(r, g, b)", "#rrggbb" or "#rgb" -> "#rrggbb" (grey when unknown).
function toHex(cssColor: string): string {
  const text = cssColor.trim().toLowerCase();
  if (HEX.test(text)) {
    return text;
  }
  const short = /^#([0-9a-f])([0-9a-f])([0-9a-f])$/.exec(text);
  if (short) {
    return `#${short[1]}${short[1]}${short[2]}${short[2]}${short[3]}${short[3]}`;
  }
  const rgb = /^rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(text);
  if (rgb) {
    return '#' +
        [rgb[1], rgb[2], rgb[3]]
            .map(v => Number(v).toString(16).padStart(2, '0'))
            .join('');
  }
  return '#808080';
}

declare global {
  interface HTMLElementTagNameMap {
    'settings-iris-theme-editor-page': SettingsIrisThemeEditorPageElement;
  }
}

customElements.define(
    SettingsIrisThemeEditorPageElement.is, SettingsIrisThemeEditorPageElement);
