// ============================================================
// MotoGo24 Doc Scanner — upload.js (send to backend)
// ============================================================

var DocUpload = {

  // ── Send document to receive-invoice edge function ─
  send: function() {
    if (!AppState.currentPhoto) {
      DebugLog.warn('UPLOAD', 'No photo to send');
      return;
    }

    DebugLog.info('UPLOAD', 'Starting upload...');
    var self = this;

    // Check network on native
    this._checkNetwork().then(function(online) {
      if (!online) {
        DebugLog.error('UPLOAD', 'No network connection');
        DocUI.showError('Neni pripojeni k internetu.');
        return;
      }
      self._doUpload();
    });
  },

  // ── Check network status ───────────────────────────
  _checkNetwork: function() {
    if (!AppState.isNative) {
      return Promise.resolve(navigator.onLine !== false);
    }
    try {
      var Network = Capacitor.Plugins.Network;
      if (!Network) return Promise.resolve(true);
      return Network.getStatus().then(function(s) {
        DebugLog.info('UPLOAD', 'Network status', s);
        return s.connected;
      }).catch(function() { return true; });
    } catch (_) {
      return Promise.resolve(true);
    }
  },

  // ── Perform the upload ─────────────────────────────
  _doUpload: function() {
    var fileName = 'scan_' + Date.now() + '.jpg';
    var payloadSize = AppState.currentPhoto.length;

    DebugLog.info('UPLOAD', 'Sending to backend, file=' + fileName +
      ' payload_base64_len=' + payloadSize);

    DocUI.showLoading('Analyzuji doklad...');
    document.getElementById('btn-send').disabled = true;

    var startTime = Date.now();

    fetch(AppConfig.EDGE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Invoice-Api-Key': AppConfig.API_KEY
      },
      body: JSON.stringify({
        image_base64: AppState.currentPhoto,
        file_name: fileName
      })
    })
    .then(function(response) {
      var elapsed = Date.now() - startTime;
      DebugLog.info('UPLOAD', 'Response status=' + response.status +
        ' time=' + elapsed + 'ms');

      return response.json().then(function(data) {
        return { ok: response.ok, status: response.status, data: data };
      });
    })
    .then(function(result) {
      DocUI.hideLoading();

      if (!result.ok) {
        var errMsg = result.data.error || 'Chyba serveru (' + result.status + ')';
        DebugLog.error('UPLOAD', 'Server error', {
          status: result.status,
          error: errMsg,
          data: result.data
        });
        DocUI.showError('Chyba: ' + errMsg);
        document.getElementById('btn-send').disabled = false;
        return;
      }

      DebugLog.info('UPLOAD', 'Upload SUCCESS', {
        document_type: result.data.document_type,
        confidence: result.data.confidence,
        needs_review: result.data.needs_review,
        financial_event_id: result.data.financial_event_id
      });

      DocUI.showResult(result.data);
      DocUI.saveToHistory({
        document_type: result.data.document_type,
        supplier: result.data.extracted && result.data.extracted.supplier,
        amount: result.data.extracted && result.data.extracted.amount,
        date: result.data.extracted && result.data.extracted.date,
        timestamp: new Date().toISOString(),
        needs_review: result.data.needs_review
      });
    })
    .catch(function(err) {
      var elapsed = Date.now() - startTime;
      DebugLog.error('UPLOAD', 'Fetch failed after ' + elapsed + 'ms', err.message || err);
      DocUI.hideLoading();
      DocUI.showError('Nepodarilo se odeslat: ' + (err.message || 'sit neni dostupna'));
      document.getElementById('btn-send').disabled = false;
    });
  }
};
