// ===== SOS-PHOTO.JS – SOS fotodokumentace =====
// Capacitor Camera plugin pro focení/výběr fotek před odesláním SOS incidentu.
// Max 5000 tokenů (VoltBuilder limit)

var _sosPhotos = []; // Array of {dataUrl, blob}
var _sosPhotoMax = 5;

// Capture photo via Capacitor Camera or fallback file input
async function captureSOSPhoto() {
  if (_sosPhotos.length >= _sosPhotoMax) {
    showT('⚠️', 'Maximum fotek', 'Můžete přidat max ' + _sosPhotoMax + ' fotek');
    return;
  }

  // Try Capacitor Camera plugin
  if (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Camera) {
    try {
      var result = await window.Capacitor.Plugins.Camera.getPhoto({
        quality: 80,
        allowEditing: false,
        resultType: 'dataUrl',
        source: 'PROMPT', // camera or gallery
        width: 2048,
        correctOrientation: true
      });
      if (result && result.dataUrl) {
        var compressed = await resizeAndCompress(result.dataUrl);
        _sosPhotos.push(compressed);
        _renderSOSPhotoPreview();
        return;
      }
    } catch (e) {
      console.warn('[SOS-PHOTO] Capacitor Camera error:', e);
    }
  }

  // Fallback: HTML file input
  _sosPhotoFallbackInput();
}

function _sosPhotoFallbackInput() {
  var input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.capture = 'environment';
  input.onchange = async function () {
    if (!input.files || !input.files[0]) return;
    var reader = new FileReader();
    reader.onload = async function (ev) {
      var compressed = await resizeAndCompress(ev.target.result);
      _sosPhotos.push(compressed);
      _renderSOSPhotoPreview();
    };
    reader.readAsDataURL(input.files[0]);
  };
  input.click();
}

// Resize image to max 2048px width, JPEG quality 80%
function resizeAndCompress(dataUrl) {
  return new Promise(function (resolve) {
    var img = new Image();
    img.onload = function () {
      var maxW = 2048;
      var w = img.width;
      var h = img.height;
      if (w > maxW) { h = Math.round(h * (maxW / w)); w = maxW; }
      var canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      var ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0, w, h);
      var jpegUrl = canvas.toDataURL('image/jpeg', 0.8);
      // Convert to blob
      var byteStr = atob(jpegUrl.split(',')[1]);
      var arr = new Uint8Array(byteStr.length);
      for (var i = 0; i < byteStr.length; i++) arr[i] = byteStr.charCodeAt(i);
      var blob = new Blob([arr], { type: 'image/jpeg' });
      resolve({ dataUrl: jpegUrl, blob: blob });
    };
    img.onerror = function () {
      resolve({ dataUrl: dataUrl, blob: null });
    };
    img.src = dataUrl;
  });
}

// Upload photos to Supabase Storage
async function uploadSOSPhotos(incidentId, photos) {
  if (!window.supabase || !photos || photos.length === 0) return [];
  var urls = [];
  for (var i = 0; i < photos.length; i++) {
    var photo = photos[i];
    if (!photo.blob) continue;
    var ts = Date.now() + '-' + i;
    var path = incidentId + '/' + ts + '.jpg';
    try {
      var r = await window.supabase.storage
        .from('sos-photos')
        .upload(path, photo.blob, { contentType: 'image/jpeg', upsert: false });
      if (!r.error) {
        urls.push('sos-photos/' + path);
      } else {
        console.warn('[SOS-PHOTO] upload error:', r.error);
      }
    } catch (e) {
      console.warn('[SOS-PHOTO] upload exception:', e);
    }
  }
  return urls;
}

// Save photo URLs to sos_incidents.photos[]
async function saveSOSPhotoUrls(incidentId, urls) {
  if (!window.supabase || !urls || urls.length === 0) return;
  try {
    await window.supabase.from('sos_incidents')
      .update({ photos: urls })
      .eq('id', incidentId);
  } catch (e) {
    console.warn('[SOS-PHOTO] save URLs error:', e);
  }
}

// Render photo previews in the photo step container
function _renderSOSPhotoPreview() {
  var wrap = document.getElementById('sos-photo-preview');
  if (!wrap) return;
  var html = '';
  for (var i = 0; i < _sosPhotos.length; i++) {
    html += '<div style="position:relative;display:inline-block;margin:4px;">' +
      '<img src="' + _sosPhotos[i].dataUrl + '" style="width:70px;height:70px;object-fit:cover;border-radius:8px;border:2px solid var(--green);">' +
      '<button onclick="_sosRemovePhoto(' + i + ')" style="position:absolute;top:-6px;right:-6px;width:20px;height:20px;background:#ef4444;color:#fff;border:none;border-radius:50%;font-size:11px;font-weight:900;cursor:pointer;line-height:20px;padding:0;">✕</button>' +
      '</div>';
  }
  wrap.innerHTML = html;
  var countEl = document.getElementById('sos-photo-count');
  if (countEl) countEl.textContent = _sosPhotos.length + '/' + _sosPhotoMax;
}

function _sosRemovePhoto(idx) {
  _sosPhotos.splice(idx, 1);
  _renderSOSPhotoPreview();
}

function _sosResetPhotos() {
  _sosPhotos = [];
  var wrap = document.getElementById('sos-photo-preview');
  if (wrap) wrap.innerHTML = '';
  var countEl = document.getElementById('sos-photo-count');
  if (countEl) countEl.textContent = '0/' + _sosPhotoMax;
}

// Inject photo step HTML into a container
function _sosInjectPhotoStep(containerId) {
  var el = document.getElementById(containerId);
  if (!el) return;
  el.innerHTML =
    '<div style="background:#fff;border-radius:var(--r);padding:14px;box-shadow:var(--shadow);margin:12px 20px;">' +
    '<div style="font-size:11px;font-weight:800;color:var(--g400);text-transform:uppercase;letter-spacing:1px;margin-bottom:10px;">' +
    '📷 Fotodokumentace <span id="sos-photo-count" style="color:var(--gd);">0/' + _sosPhotoMax + '</span></div>' +
    '<div id="sos-photo-preview" style="margin-bottom:8px;"></div>' +
    '<button onclick="captureSOSPhoto()" style="width:100%;background:var(--gp);color:var(--gd);border:2px solid var(--green);border-radius:50px;padding:12px;font-family:var(--font);font-size:13px;font-weight:700;cursor:pointer;">' +
    '📸 Vyfotit nebo vybrat z galerie</button>' +
    '<div style="font-size:10px;color:var(--g400);margin-top:6px;text-align:center;">Přidejte foto poškození (1-5 fotek)</div>' +
    '</div>';
  _sosResetPhotos();
}
