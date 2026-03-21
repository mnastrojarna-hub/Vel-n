// ============================================================
// MotoGo24 Doc Scanner — camera.js
// Uses native HTML file inputs - works on all Android devices
// without Capacitor Camera plugin dependency.
// ============================================================

var DocCamera = {

  // ── Main entry point ───────────────────────────────
  scan: function(source) {
    DebugLog.info('CAM', 'Scan requested, source=' + source);

    var inputId = source === 'CAMERA' ? 'file-input-camera' : 'file-input';
    var input = document.getElementById(inputId);
    if (!input) {
      DebugLog.error('CAM', 'File input not found: ' + inputId);
      alert('Chyba: input element nenalezen');
      return;
    }

    // Clear previous selection
    input.value = '';

    var self = this;
    input.onchange = function(e) {
      var file = e.target.files && e.target.files[0];
      if (!file) {
        DebugLog.info('CAM', 'No file selected (user cancelled)');
        return;
      }

      DebugLog.info('CAM', 'File selected: ' + file.name +
        ' size=' + Math.round(file.size / 1024) + 'KB type=' + file.type);

      if (file.size > AppConfig.MAX_SIZE_MB * 1024 * 1024) {
        DebugLog.warn('CAM', 'File too large: ' + Math.round(file.size / 1024) + 'KB');
        alert('Soubor je prilis velky (max ' + AppConfig.MAX_SIZE_MB + ' MB).');
        return;
      }

      self._fileToBase64(file);
    };

    // Trigger native file picker / camera
    DebugLog.info('CAM', 'Opening ' + (source === 'CAMERA' ? 'camera' : 'gallery') + '...');
    input.click();
  },

  // ── Convert file to base64 ─────────────────────────
  _fileToBase64: function(file) {
    DebugLog.info('CAM', 'Converting file to base64...');
    var reader = new FileReader();

    reader.onload = function(ev) {
      var dataUrl = ev.target.result;
      // Strip data:image/...;base64, prefix
      var base64 = dataUrl.split(',')[1];
      if (!base64) {
        DebugLog.error('CAM', 'Failed to extract base64 from file');
        alert('Chyba pri cteni souboru');
        return;
      }

      var sizeKB = Math.round((base64.length * 0.75) / 1024);
      DebugLog.info('CAM', 'Base64 ready, size ~' + sizeKB + 'KB, len=' + base64.length);

      AppState.currentPhoto = base64;
      DocUI.showPreview(base64);
    };

    reader.onerror = function(err) {
      DebugLog.error('CAM', 'FileReader error', err);
      alert('Chyba pri cteni souboru');
    };

    reader.readAsDataURL(file);
  }
};
