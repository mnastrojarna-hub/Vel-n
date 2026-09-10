/* MotoGo24 kiosk — dotykové klávesnice (numerická / QWERTY / textová) + fyzická klávesnice.
   Vanilla JS, bez závislostí. Rozložení a texty odpovídají Flutter kiosku (widgets/keyboards.dart). */
'use strict';
window.MG = window.MG || {};

MG.Keyboard = (function () {
  const LETTER_ROWS = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  const DIGIT_ROWS = [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']];

  /** Jedna klávesa: label, CSS třídy, akce. Vizuální stisk přes pointerdown/up. */
  function key(label, cls, onTap) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'key' + (cls ? ' ' + cls : '');
    b.textContent = label;
    b.addEventListener('pointerdown', (e) => { e.preventDefault(); b.classList.add('pressed'); });
    const release = () => b.classList.remove('pressed');
    b.addEventListener('pointerup', release);
    b.addEventListener('pointercancel', release);
    b.addEventListener('pointerleave', release);
    b.addEventListener('click', (e) => { e.preventDefault(); if (typeof onTap === 'function') onTap(); });
    return b;
  }

  function row(keys) {
    const r = document.createElement('div');
    r.className = 'kb-row';
    keys.forEach((k) => r.appendChild(k));
    return r;
  }

  function block(cls, rows) {
    const b = document.createElement('div');
    b.className = 'kb-block ' + cls;
    rows.forEach((r) => b.appendChild(r));
    return b;
  }

  /** Numerický blok jako ve Flutteru: 1-2-3 / 4-5-6 / 7-8-9 / ⌫ 0 OK. */
  function numericBlock(cls, o) {
    const rows = DIGIT_ROWS.map((r) => row(r.map((n) => key(n, '', () => o.onChar(n)))));
    rows.push(row([
      key('⌫', '', o.onBackspace),
      key('0', '', () => o.onChar('0')),
      key('✓', 'green', o.onEnter),
    ]));
    return block(cls, rows);
  }

  function letterRows(o) {
    return LETTER_ROWS.map((r) => row(r.split('').map((ch) => key(ch.toUpperCase(), 'small', () => o.onChar(ch)))));
  }

  /**
   * Postaví klávesnici do kontejneru.
   * opts: { mode: 'num'|'qwerty'|'text', onChar, onBackspace, onEnter, onClear, onToggle, enterLabel, clearLabel }
   */
  function build(container, opts) {
    const o = Object.assign({ mode: 'num', onChar() {}, onBackspace() {}, onEnter() {}, onClear() {}, onToggle() {}, clearLabel: 'SMAZAT' }, opts || {});
    container.textContent = '';
    const kb = document.createElement('div');
    kb.className = 'kb kb-' + o.mode;
    if (o.mode === 'num') {
      kb.appendChild(numericBlock('kb-num', o));
      kb.appendChild(block('kb-num-side', [
        row([key('ABC', 'small', o.onToggle)]),
        row([key(o.clearLabel, 'small amber', o.onClear)]),
      ]));
    } else if (o.mode === 'qwerty') {
      const rows = letterRows(o);
      rows.push(row([
        key('123', 'small f2', o.onToggle),
        key(o.clearLabel, 'small amber f3', o.onClear),
        key('⌫', 'f2', o.onBackspace),
      ]));
      kb.appendChild(block('kb-letters', rows));
      kb.appendChild(numericBlock('kb-digits', o));
    } else {
      const rows = [row('1234567890'.split('').map((n) => key(n, 'small', () => o.onChar(n))))];
      rows.push(...letterRows(o));
      rows.push(row([
        key('-', 'small', () => o.onChar('-')),
        key(o.clearLabel, 'small amber f2', o.onClear),
        key('⌫', 'f2', o.onBackspace),
        key(o.enterLabel || 'OK', 'small green f2', o.onEnter),
      ]));
      kb.appendChild(block('kb-text', rows));
    }
    container.appendChild(kb);
    return {
      setEnabled(enabled) { kb.classList.toggle('disabled', !enabled); },
      element: kb,
    };
  }

  /**
   * Fyzická klávesnice (numpad/USB): číslice, písmena, '-', Enter, Backspace, Escape, Delete.
   * handlers: { onChar, onBackspace, onEnter, onEscape, onClear, isActive() }
   */
  function bindPhysical(h) {
    document.addEventListener('keydown', (e) => {
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (typeof h.isActive === 'function' && !h.isActive()) return;
      const k = e.key;
      let handled = true;
      if (k.length === 1 && /[0-9a-zA-Z-]/.test(k)) h.onChar(k.toLowerCase());
      else if (k === 'Enter' || k === 'NumpadEnter') h.onEnter();
      else if (k === 'Backspace') h.onBackspace();
      else if (k === 'Escape') { if (h.onEscape) h.onEscape(); }
      else if (k === 'Delete') { if (h.onClear) h.onClear(); }
      else handled = false;
      if (handled) e.preventDefault();
    });
  }

  return { build, bindPhysical };
})();
