// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

import {html} from 'chrome://resources/lit/v3_0/lit.rollup.js';

import type {SettingsIrisAppLockElement} from './iris_app_lock.js';

export function getHtml(this: SettingsIrisAppLockElement) {
  return html`<!--_html_template_start_-->
<div style="display: flex; align-items: center; gap: 8px;
    min-height: var(--cr-section-min-height);
    padding: 0 var(--cr-section-padding);
    border-top: var(--cr-separator-line);">
  <div style="flex: 1; padding: 12px 0;">
    <div>$i18n{irisAppLock}</div>
    <div style="color: var(--cr-secondary-text-color);">
      $i18n{irisAppLockSublabel}
    </div>
  </div>
  ${this.enabled_ ? html`
    <cr-button id="change" @click="${this.onChangeClick_}">
      $i18n{irisAppLockChange}
    </cr-button>
    <cr-button id="remove" @click="${this.onRemoveClick_}">
      $i18n{irisAppLockRemove}
    </cr-button>` : html`
    <cr-button id="set" @click="${this.onSetClick_}">
      $i18n{irisAppLockSet}
    </cr-button>`}
</div>
${this.mode_ ? html`
  <cr-dialog show-on-attach close-text="$i18n{close}"
      @close="${this.onDialogClose_}">
    <div slot="title">${this.dialogTitle_()}</div>
    <div slot="body">
      ${this.needsCurrent_() ? html`
        <cr-input id="current" type="password" autofocus
            label="$i18n{irisUnlockPrompt}"></cr-input>` : ''}
      ${this.needsNew_() ? html`
        <cr-input id="new1" type="password"
            ?autofocus="${!this.needsCurrent_()}"
            label="$i18n{irisPassphraseLabel}"></cr-input>
        <cr-input id="new2" type="password"
            label="$i18n{irisPassphraseLabel}"></cr-input>
        <div style="margin-top: 12px;">$i18n{irisAppLockWarning}</div>` : ''}
      <div style="margin-top: 8px; color: var(--cr-fallback-color-error);">
        ${this.error_}
      </div>
    </div>
    <div slot="button-container">
      <cr-button class="cancel-button" @click="${this.onCancelClick_}">
        $i18n{cancel}
      </cr-button>
      <cr-button class="action-button" ?disabled="${this.busy_}"
          @click="${this.onConfirmClick_}">
        ${this.dialogTitle_()}
      </cr-button>
    </div>
  </cr-dialog>` : ''}
<!--_html_template_end_-->`;
}
