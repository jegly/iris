// Copyright 2026 jegly. Licensed under the GNU General Public License v2.0 or later.

/**
 * @fileoverview Iris (Phase B8): Settings -> Privacy and security -> "Lock Iris
 * with a passphrase". Set, change or turn off the passphrase that Iris asks
 * for when it starts (IrisAppLockHandler).
 */
import 'chrome://resources/cr_elements/cr_button/cr_button.js';
import 'chrome://resources/cr_elements/cr_dialog/cr_dialog.js';
import 'chrome://resources/cr_elements/cr_input/cr_input.js';

import type {CrDialogElement} from 'chrome://resources/cr_elements/cr_dialog/cr_dialog.js';
import type {CrInputElement} from 'chrome://resources/cr_elements/cr_input/cr_input.js';
import {I18nMixinLit} from 'chrome://resources/cr_elements/i18n_mixin_lit.js';
import {sendWithPromise} from 'chrome://resources/js/cr.js';
import {CrLitElement} from 'chrome://resources/lit/v3_0/lit.rollup.js';

import {getHtml} from './iris_app_lock.html.js';

export type IrisAppLockMode = ''|'set'|'change'|'remove';

const SettingsIrisAppLockElementBase = I18nMixinLit(CrLitElement);

export class SettingsIrisAppLockElement extends SettingsIrisAppLockElementBase {
  static get is() {
    return 'settings-iris-app-lock';
  }

  override render() {
    return getHtml.bind(this)();
  }

  static override get properties() {
    return {
      enabled_: {type: Boolean},
      mode_: {type: String},
      error_: {type: String},
      busy_: {type: Boolean},
    };
  }

  protected accessor enabled_: boolean = false;
  protected accessor mode_: IrisAppLockMode = '';
  protected accessor error_: string = '';
  protected accessor busy_: boolean = false;

  override connectedCallback() {
    super.connectedCallback();
    sendWithPromise<boolean>('irisAppLockGetStatus').then(enabled => {
      this.enabled_ = enabled;
    });
  }

  protected dialogTitle_(): string {
    switch (this.mode_) {
      case 'set':
        return this.i18n('irisAppLockSet');
      case 'change':
        return this.i18n('irisAppLockChange');
      case 'remove':
        return this.i18n('irisAppLockRemove');
      default:
        return '';
    }
  }

  protected needsCurrent_(): boolean {
    return this.mode_ === 'change' || this.mode_ === 'remove';
  }

  protected needsNew_(): boolean {
    return this.mode_ === 'set' || this.mode_ === 'change';
  }

  protected onSetClick_() {
    this.open_('set');
  }

  protected onChangeClick_() {
    this.open_('change');
  }

  protected onRemoveClick_() {
    this.open_('remove');
  }

  private open_(mode: IrisAppLockMode) {
    this.error_ = '';
    this.busy_ = false;
    this.mode_ = mode;
  }

  private value_(id: string): string {
    const input = this.shadowRoot.querySelector<CrInputElement>(`#${id}`);
    return input ? input.value : '';
  }

  protected onCancelClick_() {
    this.shadowRoot.querySelector<CrDialogElement>('cr-dialog')?.close();
  }

  protected onDialogClose_() {
    this.mode_ = '';
  }

  protected async onConfirmClick_() {
    const current = this.value_('current');
    let result: string;
    if (this.needsNew_()) {
      const first = this.value_('new1');
      if (first === '') {
        return;
      }
      if (first !== this.value_('new2')) {
        this.error_ = this.i18n('irisPassphraseMismatch');
        return;
      }
      this.busy_ = true;
      result = await sendWithPromise('irisAppLockSet', current, first);
    } else {
      this.busy_ = true;
      result = await sendWithPromise('irisAppLockRemove', current);
    }
    this.busy_ = false;
    if (result === 'wrong') {
      this.error_ = this.i18n('irisUnlockWrong');
      return;
    }
    if (result !== 'ok') {
      return;
    }
    this.enabled_ = this.mode_ !== 'remove';
    this.onCancelClick_();
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'settings-iris-app-lock': SettingsIrisAppLockElement;
  }
}

customElements.define(
    SettingsIrisAppLockElement.is, SettingsIrisAppLockElement);
