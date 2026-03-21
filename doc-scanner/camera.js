// ============================================================
// MotoGo24 Doc Scanner — camera.js
// Uses Capacitor Camera plugin with proper Android permission
// requests. Falls back to HTML file inputs if Capacitor is
// not available (web browser).
// ============================================================

var DocCamera = {

  // ── Main entry point ───────────────────────────────
  scan: function(source) {
    DebugLog.info('CAM', 'Scan requested, source=' + source);

    // Try Capacitor Camera plugin first (handles Android permissions)
    if (this._hasCapacitorCamera()) {
      this._scanWithCapacitor(source);
    } else {
      DebugLog.info('CAM', 'Capacitor Camera not available, using file input fallback');
      this._scanWithFileInput(source);
    }
  },

  // ── Check if Capacitor Camera is available ─────────
  _hasCapacitorCamera: function() {
    return !!(window.Capacitor &&
              window.Capacitor.Plugins &&
              window.Capacitor.Plugins.Camera);
  },

  // ── Capacitor Camera (requests Android permissions) ─
  _scanWithCapacitor: function(source) {
    var self = this;
    var Camera = window.Capacitor.Plugins.Camera;

    // Map source to Capacitor CameraSource
    var cameraSource = source === 'CAMERA' ? 'CAMERA' : 'PHOTOS';

    DebugLog.info('CAM', 'Requesting camera permission via Capacitor...');

    // checkPermissions + requestPermissions ensures Android shows
    // the system permission dialog before opening the camera
    Camera.checkPermissions().then(function(status) {
      DebugLog.info('CAM', 'Permission status', status);

      var needsRequest = false;
      if (cameraSource === 'CAMERA' && status.camera !== 'granted') {
        needsRequest = true;
      }
      if (cameraSource === 'PHOTOS' && status.photos !== 'granted') {
        needsRequest = true;
      }

      if (needsRequest) {
        DebugLog.info('CAM', 'Requesting permissions...');
        return Camera.requestPermissions({
          permissions: cameraSource === 'CAMERA' ? ['camera'] : ['photos']
        });
      }
      return status;
    }).then(function(permResult) {
      DebugLog.info('CAM', 'Permission result', permResult);

      // Check if permission was denied
      if (cameraSource === 'CAMERA' && permResult && permResult.camera === 'denied') {
        DebugLog.error('CAM', 'Camera permission denied by user');
        alert('Pristup k fotoaparatu byl zamitnut. Povolte ho v nastaveni aplikace.');
        return;
      }

      DebugLog.info('CAM', 'Opening Capacitor Camera, source=' + cameraSource);
      return Camera.getPhoto({
        quality: 90,
        allowEditing: false,
        resultType: 'base64',
        source: cameraSource,
        width: 3840,
        correctOrientation: true
      });
    }).then(function(photo) {
      if (!photo || !photo.base64String) {
        DebugLog.info('CAM', 'No photo returned (user cancelled)');
        return;
      }

      var sizeKB = Math.round((photo.base64String.length * 0.75) / 1024);
      DebugLog.info('CAM', 'Photo captured via Capacitor, ~' + sizeKB + 'KB');

      AppState.currentPhoto = photo.base64String;
      DocUI.showPreview(photo.base64String);
    }).catch(function(err) {
      var msg = (err && err.message) || String(err);
      DebugLog.error('CAM', 'Capacitor Camera error: ' + msg);

      // User cancelled — not an error
      if (msg.indexOf('cancel') !== -1 || msg.indexOf('Cancel') !== -1 ||
          msg.indexOf('dismissed') !== -1 || msg.indexOf('User') !== -1) {
        DebugLog.info('CAM', 'User cancelled photo capture');
        return;
      }

      // Permission denied
      if (msg.indexOf('permission') !== -1 || msg.indexOf('denied') !== -1) {
        alert('Pristup k fotoaparatu byl zamitnut. Povolte ho v nastaveni aplikace.');
        return;
      }

      // Other error — fall back to file input
      DebugLog.warn('CAM', 'Falling back to file input after Capacitor error');
      self._scanWithFileInput(source);
    });
  },

  // ── File input fallback (web browser) ──────────────
  _scanWithFileInput: function(source) {
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
    DebugLog.info('CAM', 'Opening ' + (source === 'CAMERA' ? 'camera' : 'gallery') + ' via file input...');
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
