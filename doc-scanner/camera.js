// ============================================================
// MotoGo24 Doc Scanner — camera.js (permissions + capture)
// ============================================================

var DocCamera = {

  // ── Request Android camera permissions ─────────────
  requestPermissions: function() {
    DebugLog.info('CAM', 'Requesting camera permissions...');

    if (!AppState.isNative) {
      DebugLog.info('CAM', 'Web mode - no native permissions needed');
      AppState.hasCamera = true;
      return Promise.resolve(true);
    }

    // Capacitor Camera plugin
    try {
      var Camera = Capacitor.Plugins.Camera;
      if (!Camera) {
        DebugLog.error('CAM', 'Camera plugin not available');
        AppState.hasCamera = false;
        return Promise.resolve(false);
      }

      return Camera.requestPermissions({ permissions: ['camera', 'photos'] })
        .then(function(result) {
          DebugLog.info('CAM', 'Permission result', result);
          if (result.camera === 'granted' || result.camera === 'limited') {
            AppState.hasCamera = true;
            DebugLog.info('CAM', 'Camera permission GRANTED');
          } else {
            AppState.hasCamera = false;
            DebugLog.warn('CAM', 'Camera permission DENIED: ' + result.camera);
          }
          return AppState.hasCamera;
        })
        .catch(function(err) {
          DebugLog.error('CAM', 'Permission request failed', err.message || err);
          AppState.hasCamera = false;
          return false;
        });
    } catch (e) {
      DebugLog.error('CAM', 'Permission exception', e.message);
      AppState.hasCamera = false;
      return Promise.resolve(false);
    }
  },

  // ── Main scan entry point ──────────────────────────
  scan: function(source) {
    DebugLog.info('CAM', 'Scan requested, source=' + source);

    if (AppState.isNative) {
      this._scanNative(source);
    } else {
      this._scanWeb(source);
    }
  },

  // ── Native Capacitor camera ────────────────────────
  _scanNative: function(source) {
    var self = this;
    DebugLog.info('CAM', 'Native scan: ' + source);

    var Camera = Capacitor.Plugins.Camera;
    if (!Camera) {
      DebugLog.error('CAM', 'Camera plugin not found - falling back to web');
      this._scanWeb(source);
      return;
    }

    // Map source
    var capSource = source === 'PHOTOS' ? 'PHOTOS' : 'CAMERA';

    // Check permissions first
    Camera.checkPermissions().then(function(perms) {
      DebugLog.info('CAM', 'Current permissions', perms);

      if (perms.camera !== 'granted' && capSource === 'CAMERA') {
        DebugLog.info('CAM', 'Requesting camera permission...');
        return Camera.requestPermissions({ permissions: ['camera'] })
          .then(function(result) {
            if (result.camera !== 'granted') {
              DebugLog.error('CAM', 'Camera permission denied by user');
              alert('Pro foceni je potreba povolit pristup k fotoaparatu v nastaveni.');
              return null;
            }
            return self._takePhoto(Camera, capSource);
          });
      }
      return self._takePhoto(Camera, capSource);
    }).catch(function(err) {
      DebugLog.error('CAM', 'Permission check failed', err.message);
      self._scanWeb(source);
    });
  },

  // ── Take photo via Capacitor ───────────────────────
  _takePhoto: function(Camera, source) {
    DebugLog.info('CAM', 'Taking photo, source=' + source);

    return Camera.getPhoto({
      quality: 85,
      allowEditing: false,
      resultType: 'base64',
      source: source,
      correctOrientation: true,
      width: 1600,
      height: 1600,
      presentationStyle: 'fullscreen'
    }).then(function(photo) {
      DebugLog.info('CAM', 'Photo captured, format=' + photo.format +
        ' base64len=' + (photo.base64String ? photo.base64String.length : 0));

      if (!photo.base64String) {
        DebugLog.error('CAM', 'Empty base64 from camera');
        return;
      }

      var sizeKB = (photo.base64String.length * 0.75) / 1024;
      DebugLog.info('CAM', 'Image size: ~' + Math.round(sizeKB) + ' KB');

      if (sizeKB > AppConfig.MAX_SIZE_MB * 1024) {
        DebugLog.warn('CAM', 'Image too large: ' + Math.round(sizeKB) + ' KB');
        alert('Soubor je prilis velky (max ' + AppConfig.MAX_SIZE_MB + ' MB).');
        return;
      }

      AppState.currentPhoto = photo.base64String;
      DocUI.showPreview(photo.base64String);
    }).catch(function(err) {
      if (err.message && err.message.indexOf('cancel') !== -1) {
        DebugLog.info('CAM', 'User cancelled camera');
        return;
      }
      DebugLog.error('CAM', 'Camera getPhoto error', err.message || err);
    });
  },

  // ── Web fallback (file input) ──────────────────────
  _scanWeb: function(source) {
    DebugLog.info('CAM', 'Web fallback scan: ' + source);
    var self = this;

    var inputId = source === 'CAMERA' ? 'file-input-camera' : 'file-input';
    var input = document.getElementById(inputId);
    if (!input) {
      DebugLog.error('CAM', 'File input element not found: ' + inputId);
      return;
    }

    // Clear previous selection
    input.value = '';

    input.onchange = function(e) {
      var file = e.target.files && e.target.files[0];
      if (!file) {
        DebugLog.info('CAM', 'No file selected');
        return;
      }
      DebugLog.info('CAM', 'File selected: ' + file.name +
        ' size=' + Math.round(file.size / 1024) + 'KB type=' + file.type);

      if (file.size > AppConfig.MAX_SIZE_MB * 1024 * 1024) {
        DebugLog.warn('CAM', 'File too large');
        alert('Soubor je prilis velky (max ' + AppConfig.MAX_SIZE_MB + ' MB).');
        return;
      }

      self._fileToBase64(file);
    };

    input.click();
  },

  // ── Convert file to base64 ─────────────────────────
  _fileToBase64: function(file) {
    var reader = new FileReader();
    reader.onload = function(ev) {
      var dataUrl = ev.target.result;
      // Strip data:image/...;base64, prefix
      var base64 = dataUrl.split(',')[1];
      if (!base64) {
        DebugLog.error('CAM', 'Failed to extract base64 from file');
        return;
      }
      DebugLog.info('CAM', 'File converted to base64, len=' + base64.length);
      AppState.currentPhoto = base64;
      DocUI.showPreview(base64);
    };
    reader.onerror = function() {
      DebugLog.error('CAM', 'FileReader error');
    };
    reader.readAsDataURL(file);
  }
};
