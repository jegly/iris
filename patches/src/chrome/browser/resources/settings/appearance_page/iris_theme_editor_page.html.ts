// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

import {html} from '//resources/lit/v3_0/lit.rollup.js';

import type {SettingsIrisThemeEditorPageElement} from './iris_theme_editor_page.js';

export function getHtml(this: SettingsIrisThemeEditorPageElement) {
  // clang-format off
  return html`<!--_html_template_start_-->
<settings-subpage page-title="Theme editor" route-path="${this.routePath}">
  <div class="cr-row first">
    <div class="flex cr-padded-text">
      Pick a colour for any part of Iris. Anything you leave alone keeps the
      colour of your palette. Changes show straight away.
    </div>
    <cr-button id="resetAll" @click="${this.onResetAllClick_}">
      Reset all
    </cr-button>
  </div>

  ${this.groups_.map(group => html`
    <div class="cr-row group-title">${group.title}</div>
    ${group.items.map(item => html`
      <div class="cr-row swatch-row">
        <div class="label cr-padded-text">
          ${item.label}
          ${!this.isSet_(item.key) ? html`
            <div class="from-palette">From your palette</div>` : ''}
        </div>
        <input type="color" data-key="${item.key}"
            aria-label="${item.label}"
            .value="${this.swatchValue_(item)}"
            @change="${this.onColorChange_}">
        <cr-button data-key="${item.key}" ?hidden="${!this.isSet_(item.key)}"
            @click="${this.onResetItemClick_}">Reset</cr-button>
      </div>
    `)}
  `)}

  <div class="cr-row group-title">Websites</div>
  <settings-toggle-button id="recolorToggle" class="hr"
      pref-key="iris.web_recolor.enabled"
      label="Recolour websites"
      sub-label="Draws web pages in your theme's background, text and accent colours, like a dark-mode extension but built in. Pages are not changed, only how Iris draws them. If a site looks wrong, turn it off for that site in the shield. Colour changes reach pages you open afterwards.">
  </settings-toggle-button>
  <div class="cr-row" ?hidden="${!this.recolorEnabledPref_?.value}">
    <div class="flex cr-padded-text">Brightness</div>
    <input type="range" min="50" max="150" step="5"
        aria-label="Brightness of recoloured pages"
        data-pref="iris.web_recolor.brightness"
        .value="${String(this.recolorBrightnessPref_?.value ?? 100)}"
        @change="${this.onRecolorSliderChange_}">
    <div class="cr-padded-text">${this.recolorBrightnessPref_?.value ?? 100}%</div>
  </div>
  <div class="cr-row" ?hidden="${!this.recolorEnabledPref_?.value}">
    <div class="flex cr-padded-text">Contrast</div>
    <input type="range" min="50" max="150" step="5"
        aria-label="Contrast of recoloured pages"
        data-pref="iris.web_recolor.contrast"
        .value="${String(this.recolorContrastPref_?.value ?? 100)}"
        @change="${this.onRecolorSliderChange_}">
    <div class="cr-padded-text">${this.recolorContrastPref_?.value ?? 100}%</div>
  </div>

  <div class="cr-row group-title">Your themes</div>
  ${this.savedThemes_().map((theme, index) => html`
    <div class="cr-row swatch-row">
      <div class="label cr-padded-text">${theme.name}</div>
      <cr-button data-index="${index}" @click="${this.onApplyThemeClick_}">
        Use
      </cr-button>
      <cr-button data-index="${index}" @click="${this.onDeleteThemeClick_}">
        Delete
      </cr-button>
    </div>
  `)}
  <div class="cr-row code-row">
    <cr-input id="themeName" label="Save the current colours as"
        placeholder="Theme name" .value="${this.themeName_}"
        @input="${this.onThemeNameInput_}"></cr-input>
    <cr-button @click="${this.onSaveThemeClick_}">Save</cr-button>
  </div>

  <div class="cr-row group-title">Share</div>
  <div class="cr-row code-row">
    <cr-input id="themeCode" label="Theme code"
        placeholder="Paste a theme code here" .value="${this.themeCode_}"
        @input="${this.onThemeCodeInput_}"></cr-input>
    <cr-button @click="${this.onImportClick_}">Apply code</cr-button>
    <cr-button @click="${this.onExportClick_}">Copy my code</cr-button>
  </div>
  <div class="cr-row">
    <div class="note">
      A theme code holds only colours. Nothing is uploaded.
    </div>
  </div>
  <div class="cr-row" ?hidden="${!this.message_}">
    <div class="${this.messageIsError_ ? 'error' : 'note'}" role="status">
      ${this.message_}
    </div>
  </div>
</settings-subpage>
<!--_html_template_end_-->`;
  // clang-format on
}
