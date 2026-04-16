// ===== AI-AGENT-PHOTOS.JS – Photo capture, resize & preview =====
// Split from ai-agent-ui.js. Depends on: ai-agent-ui.js (shared state vars)

// ─── Photo capture (reuses resizeAndCompress from sos-photo.js) ───

function aiAgentCapturePhoto() {
  if (_aiAgentPhotos.length >= _aiAgentPhotoMax) {
    showT('\u26a0\ufe0f', 'Maximum fotek', 'M\u016f\u017eete p\u0159idat max ' + _aiAgentPhotoMax + ' fotek');
    return;
  }
  if (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Camera) {
    window.Capacitor.Plugins.Camera.getPhoto({
      quality: 80, allowEditing: false, resultType: 'dataUrl',
      source: 'PROMPT', width: 1024, correctOrientation: true
    }).then(function(result) {
      if (result && result.dataUrl) _aiAddPhoto(result.dataUrl);
    }).catch(function(e) {
      console.warn('[AI-PHOTO] Camera error:', e);
      _aiPhotoPicker();
    });
  } else {
    _aiPhotoPicker();
  }
}

function _aiPhotoPicker() {
  var input = document.createElement('input');
  input.type = 'file'; input.accept = 'image/*'; input.capture = 'environment';
  input.onchange = function() {
    if (!input.files || !input.files[0]) return;
    var reader = new FileReader();
    reader.onload = function(ev) { _aiAddPhoto(ev.target.result); };
    reader.readAsDataURL(input.files[0]);
  };
  input.click();
}

function _aiAddPhoto(dataUrl) {
  _aiResizePhoto(dataUrl).then(function(compressed) {
    _aiAgentPhotos.push(compressed);
    _renderAiPhotoPreview();
  });
}

function _aiResizePhoto(dataUrl) {
  return new Promise(function(resolve) {
    var img = new Image();
    img.onload = function() {
      var maxW = 1024;
      var w = img.width, h = img.height;
      if (w > maxW) { h = Math.round(h * (maxW / w)); w = maxW; }
      var canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      canvas.getContext('2d').drawImage(img, 0, 0, w, h);
      var jpegUrl = canvas.toDataURL('image/jpeg', 0.85);
      var base64 = jpegUrl.split(',')[1];
      resolve({ dataUrl: jpegUrl, base64: base64, mediaType: 'image/jpeg' });
    };
    img.onerror = function() { resolve({ dataUrl: dataUrl, base64: null, mediaType: null }); };
    img.src = dataUrl;
  });
}

function _renderAiPhotoPreview() {
  var wrap = document.getElementById('ai-agent-photo-preview');
  if (!wrap) return;
  if (_aiAgentPhotos.length === 0) { wrap.innerHTML = ''; return; }
  var html = '<div style="display:flex;gap:6px;align-items:center;padding:6px 0;">';
  for (var i = 0; i < _aiAgentPhotos.length; i++) {
    html += '<div style="position:relative;"><img src="' + _aiAgentPhotos[i].dataUrl +
      '" style="width:52px;height:52px;object-fit:cover;border-radius:8px;border:2px solid var(--green);">' +
      '<button onclick="_aiRemovePhoto(' + i + ')" style="position:absolute;top:-5px;right:-5px;width:18px;height:18px;background:#ef4444;color:#fff;border:none;border-radius:50%;font-size:10px;font-weight:900;cursor:pointer;line-height:18px;padding:0;">\u2715</button></div>';
  }
  html += '<span style="font-size:10px;color:var(--g400);">' + _aiAgentPhotos.length + '/' + _aiAgentPhotoMax + '</span></div>';
  wrap.innerHTML = html;
}

function _aiRemovePhoto(idx) {
  _aiAgentPhotos.splice(idx, 1);
  _renderAiPhotoPreview();
}
