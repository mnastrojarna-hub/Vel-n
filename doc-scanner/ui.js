// ============================================================
// MotoGo24 Doc Scanner — ui.js (screens, results, history)
// ============================================================

var DOC_TYPES = {
  invoice: 'Faktura',
  receipt: 'Paragon',
  contract_purchase: 'Kupni smlouva',
  contract_loan: 'Uverova smlouva',
  contract_employment: 'Pracovni smlouva',
  contract_service: 'Smlouva o sluzbach',
  insurance: 'Pojistna smlouva',
  delivery_note: 'Dodaci list',
  leasing: 'Leasingova smlouva',
  other: 'Jiny dokument'
};

var DocUI = {

  // ── Screen navigation ──────────────────────────────
  showScreen: function(name) {
    document.getElementById('screen-main').hidden = name !== 'main';
    document.getElementById('screen-preview').hidden = name !== 'preview';
    document.getElementById('screen-result').hidden = name !== 'result';
    DebugLog.info('UI', 'Screen: ' + name);
  },

  resetToMain: function() {
    AppState.currentPhoto = null;
    document.getElementById('btn-send').disabled = false;
    document.getElementById('error-box').hidden = true;
    this.showScreen('main');
    this.renderHistory();
  },

  // ── Preview ────────────────────────────────────────
  showPreview: function(base64) {
    this.showScreen('preview');
    document.getElementById('preview-img').src = 'data:image/jpeg;base64,' + base64;
    document.getElementById('error-box').hidden = true;
    DebugLog.info('UI', 'Preview shown');
  },

  // ── Loading overlay ────────────────────────────────
  showLoading: function(text) {
    document.getElementById('loading-text').textContent = text || 'Nacitam...';
    document.getElementById('loading-overlay').hidden = false;
  },

  hideLoading: function() {
    document.getElementById('loading-overlay').hidden = true;
  },

  // ── Error display ──────────────────────────────────
  showError: function(msg) {
    var box = document.getElementById('error-box');
    box.textContent = msg;
    box.hidden = false;
    DebugLog.error('UI', 'Error shown: ' + msg);
  },

  // ── Result display ─────────────────────────────────
  showResult: function(data) {
    this.hideLoading();
    this.showScreen('result');

    var icon = data.needs_review ? '!!' : 'OK';
    var docType = DOC_TYPES[data.document_type] || data.document_type;
    var supplier = '-';
    var amount = '-';
    var date = '-';

    if (data.extracted) {
      supplier = data.extracted.supplier || '-';
      amount = data.extracted.amount ? data.extracted.amount + ' Kc' : '-';
      date = data.extracted.date || '-';
    }

    document.getElementById('result-icon').textContent = icon;
    document.getElementById('result-message').textContent = data.needs_review
      ? 'Doklad odeslan - ke kontrole'
      : 'Doklad uspesne zpracovan';
    document.getElementById('result-type').textContent = docType;
    document.getElementById('result-supplier').textContent = supplier;
    document.getElementById('result-amount').textContent = amount;
    document.getElementById('result-date').textContent = date;

    var banner = document.getElementById('review-banner');
    if (data.needs_review) {
      banner.hidden = false;
      banner.textContent = 'Nizka citelnost - ke kontrole ve Velinu';
    } else {
      banner.hidden = true;
    }
  },

  // ── History ────────────────────────────────────────
  saveToHistory: function(item) {
    var history = JSON.parse(localStorage.getItem('doc_history') || '[]');
    history.unshift(item);
    if (history.length > 5) history = history.slice(0, 5);
    localStorage.setItem('doc_history', JSON.stringify(history));
    this.renderHistory();
    DebugLog.info('UI', 'History saved, count=' + history.length);
  },

  renderHistory: function() {
    var history = JSON.parse(localStorage.getItem('doc_history') || '[]');
    var container = document.getElementById('history-list');
    if (!container) return;

    if (history.length === 0) {
      container.innerHTML = '<div class="history-empty">Zatim zadne odeslane doklady</div>';
      return;
    }

    container.innerHTML = history.map(function(item) {
      var type = DOC_TYPES[item.document_type] || item.document_type || '?';
      var supplier = item.supplier || '-';
      var amount = item.amount ? item.amount + ' Kc' : '';
      var reviewMark = item.needs_review ? ' !!' : '';
      return '<div class="history-item">' +
        '<div class="hi-left">' +
          '<span class="hi-type">' + type + reviewMark + '</span>' +
          '<span class="hi-supplier">' + supplier + '</span>' +
        '</div>' +
        (amount ? '<span class="hi-amount">' + amount + '</span>' : '') +
      '</div>';
    }).join('');
  }
};
