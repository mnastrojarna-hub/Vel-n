// ===== AI-AGENT-UI.JS – AI Servisní agent chat pro zákazníky =====
// Diagnostika závad motorek přes AI (Anthropic Claude via Edge Function ai-moto-agent)
// Podporuje fotky kontrolek/budíků (base64 → Claude Vision)
// Max 5000 tokenů (VoltBuilder limit)

var _aiAgentHistory = [];
var _aiAgentSending = false;
var _aiAgentBookingId = null;
var _aiAgentPhotos = []; // Array of {dataUrl, base64, mediaType}
var _aiAgentPhotoMax = 3;

function aiAgentOpen(bookingId) {
  _aiAgentHistory = [];
  _aiAgentSending = false;
  _aiAgentPhotos = [];
  _aiAgentBookingId = bookingId || _sosCurrentBookingId || null;
  goTo('s-ai-agent');
  setTimeout(function() {
    var msgs = document.getElementById('ai-agent-msgs');
    if (msgs) msgs.innerHTML =
      '<div class="ai-msg bot"><div class="ai-bubble">' +
      '👋 Ahoj! Jsem AI servisní technik MotoGo24.<br><br>' +
      'Mám přehled o vašich rezervacích i návody k motorkám. Pomohu vám s:<br>' +
      '🔍 Diagnostika závady<br>' +
      '🛠️ Řešení na místě<br>' +
      '📖 Návod k obsluze a funkce motorky<br><br>' +
      '<strong>📸 Tip:</strong> Vyfoťte kontrolky na budíku — pomohou mi přesněji diagnostikovat problém.<br><br>' +
      '<em>Např.: "Svítí kontrolka motoru", "Jak přepnu jízdní mód?"</em></div></div>';
    var inp = document.getElementById('ai-agent-input');
    if (inp) inp.value = '';
    _updateAiAgentSosBtn(false);
    _renderAiPhotoPreview();
  }, 80);
}

// Capture photo for AI agent (reuses resizeAndCompress from sos-photo.js)
async function aiAgentCapturePhoto() {
  if (_aiAgentPhotos.length >= _aiAgentPhotoMax) {
    showT('⚠️', 'Maximum fotek', 'Můžete přidat max ' + _aiAgentPhotoMax + ' fotek');
    return;
  }
  if (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Camera) {
    try {
      var result = await window.Capacitor.Plugins.Camera.getPhoto({
        quality: 80, allowEditing: false, resultType: 'dataUrl',
        source: 'PROMPT', width: 1024, correctOrientation: true
      });
      if (result && result.dataUrl) {
        _aiAddPhoto(result.dataUrl); return;
      }
    } catch (e) { console.warn('[AI-PHOTO] Camera error:', e); }
  }
  // Fallback file input
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

async function _aiAddPhoto(dataUrl) {
  // Resize to 1024px for AI (smaller than SOS photos)
  var compressed = await _aiResizePhoto(dataUrl);
  _aiAgentPhotos.push(compressed);
  _renderAiPhotoPreview();
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

async function aiAgentSend() {
  if (_aiAgentSending) return;
  var inp = document.getElementById('ai-agent-input');
  var txt = (inp ? inp.value : '').trim();
  var hasPhotos = _aiAgentPhotos.length > 0;
  if (!txt && !hasPhotos) return;
  var msgs = document.getElementById('ai-agent-msgs');
  if (!msgs) return;

  // Show user message with photo thumbs
  var userHtml = '<div class="ai-msg user"><div class="ai-bubble">';
  if (hasPhotos) {
    userHtml += '<div style="display:flex;gap:4px;flex-wrap:wrap;margin-bottom:6px;">';
    for (var i = 0; i < _aiAgentPhotos.length; i++) {
      userHtml += '<img src="' + _aiAgentPhotos[i].dataUrl + '" style="width:60px;height:60px;object-fit:cover;border-radius:6px;">';
    }
    userHtml += '</div>';
  }
  if (txt) userHtml += txt.replace(/</g, '&lt;').replace(/>/g, '&gt;');
  else if (hasPhotos) userHtml += '<em>📸 Fotka kontrolek</em>';
  userHtml += '</div></div>';
  msgs.innerHTML += userHtml;
  if (inp) inp.value = '';
  msgs.scrollTop = msgs.scrollHeight;

  // Build images array for API
  var images = [];
  for (var j = 0; j < _aiAgentPhotos.length; j++) {
    if (_aiAgentPhotos[j].base64) {
      images.push({ base64: _aiAgentPhotos[j].base64, media_type: _aiAgentPhotos[j].mediaType });
    }
  }
  var msgText = txt || 'Podívej se na fotku kontrolek/budíku a řekni mi co to znamená.';
  _aiAgentHistory.push({ role: 'user', content: msgText });
  _aiAgentPhotos = [];
  _renderAiPhotoPreview();
  _aiAgentSending = true;

  // Show typing
  var typId = 'ai-agent-typ-' + Date.now();
  msgs.innerHTML += '<div class="ai-msg bot" id="' + typId + '">' +
    '<div class="ai-bubble" style="color:var(--g400);">⏳ Analyzuji' + (images.length ? ' fotky' : '') + '...</div></div>';
  msgs.scrollTop = msgs.scrollHeight;

  var btn = document.getElementById('ai-agent-send-btn');
  if (btn) { btn.disabled = true; btn.textContent = '⏳'; }

  try {
    if (!window.supabase) throw new Error('No connection');
    var body = {
      message: msgText,
      booking_id: _aiAgentBookingId,
      conversation_history: _aiAgentHistory.slice(-10)
    };
    if (images.length > 0) body.images = images;

    var r = await window.supabase.functions.invoke('ai-moto-agent', { body: body });
    if (r.error) throw r.error;
    var data = r.data || {};
    var reply = data.reply || 'Odpověď nedostupná. Zkuste to znovu.';
    _aiAgentHistory.push({ role: 'assistant', content: reply });

    var typEl = document.getElementById(typId);
    if (typEl) {
      typEl.querySelector('.ai-bubble').innerHTML =
        reply.replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');
    }
    _updateAiAgentSosBtn(data.suggest_sos === true);
  } catch (e) {
    console.warn('[AI-AGENT]', e);
    var typEl2 = document.getElementById(typId);
    if (typEl2) {
      typEl2.querySelector('.ai-bubble').innerHTML =
        '❌ Nepodařilo se spojit s AI asistentem. Zkuste to znovu nebo zavolejte +420 774 256 271.';
    }
  } finally {
    _aiAgentSending = false;
    if (btn) { btn.disabled = false; btn.textContent = '➤'; }
    if (msgs) msgs.scrollTop = msgs.scrollHeight;
  }
}

function _updateAiAgentSosBtn(show) {
  var el = document.getElementById('ai-agent-sos-wrap');
  if (el) el.style.display = show ? 'block' : 'none';
}

// Template for s-ai-agent screen
Templates['s-ai-agent'] = [
  '<div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);">',
  '<div class="sos-sub-back" onclick="histBack()"><div class="sos-sub-back-btn">\u2190</div>',
  '<div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zp\u011bt</div></div>',
  '<div style="font-size:28px;margin-bottom:8px;">🤖</div>',
  '<h2 style="color:#fff;font-size:20px;font-weight:900;">AI Servisn\u00ed technik</h2>',
  '<p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Diagnostika z\u00e1vad va\u0161\u00ed motorky \u2022 fotky kontrolek</p>',
  '</div>',
  '<div class="ai-chat-wrap" style="margin-top:0;">',
  '<div class="ai-chat-msgs" id="ai-agent-msgs" style="min-height:250px;max-height:50vh;"></div>',
  '<div id="ai-agent-sos-wrap" style="display:none;padding:8px 12px;">',
  '<button onclick="goTo(\'s-sos\')" style="width:100%;background:#b91c1c;color:#fff;border:none;',
  'border-radius:50px;padding:12px;font-family:var(--font);font-size:13px;font-weight:800;cursor:pointer;">',
  '\ud83c\udd98 P\u0159ej\u00edt na SOS</button></div>',
  '<div id="ai-agent-photo-preview" style="padding:0 12px;"></div>',
  '<div class="ai-chat-input">',
  '<button onclick="aiAgentCapturePhoto()" style="width:36px;height:36px;flex-shrink:0;background:var(--gp);',
  'border:2px solid var(--green);border-radius:var(--rsm);cursor:pointer;font-size:16px;display:flex;',
  'align-items:center;justify-content:center;" title="Vyfotit kontrolky">📷</button>',
  '<input type="text" id="ai-agent-input" placeholder="Popi\u0161te probl\u00e9m nebo po\u0161lete fotku..." ',
  'onkeydown="if(event.key===\'Enter\')aiAgentSend()" style="min-width:0;">',
  '<button id="ai-agent-send-btn" onclick="aiAgentSend()" ',
  'style="white-space:nowrap;flex-shrink:0;padding:10px 12px;">➤</button>',
  '</div></div>'
].join('');
