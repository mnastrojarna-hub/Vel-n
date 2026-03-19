// ===== AI-AGENT-UI.JS – AI Servisní agent chat s multi-konverzacemi =====
// Diagnostika závad motorek přes AI (Anthropic Claude via Edge Function ai-moto-agent)
// Podporuje fotky kontrolek/budíků (base64 → Claude Vision)
// Persistence: Supabase tabulka ai_customer_conversations
// Max 5000 tokenů (VoltBuilder limit)

var _aiConvList = [];
var _aiActiveConvId = null;
var _aiActiveConv = null;
var _aiAgentSending = false;
var _aiAgentBookingId = null;
var _aiAgentPhotos = [];
var _aiAgentPhotoMax = 3;
var _aiConvListOpen = false;

// ─── UUID generator (Cordova safe) ───

function _aiGenUUID() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    var r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

// ─── Entry point ───

function aiAgentOpen(bookingId) {
  _aiAgentSending = false;
  _aiAgentPhotos = [];
  _aiAgentBookingId = bookingId || _sosCurrentBookingId || null;
  _aiConvListOpen = false;
  goTo('s-ai-agent');
  setTimeout(function() {
    _aiLoadConversations();
  }, 80);
}

// ─── Load conversations list from Supabase ───

function _aiLoadConversations() {
  if (!window.supabase) {
    _aiShowOffline(); return;
  }
  var uid = _aiGetUserId();
  if (!uid) { _aiShowOffline(); return; }

  window.supabase
    .from('ai_customer_conversations')
    .select('id, title, booking_id, created_at, updated_at')
    .eq('user_id', uid)
    .order('updated_at', { ascending: false })
    .limit(50)
    .then(function(res) {
      if (res.error) {
        console.warn('[AI-CONV] load error:', res.error);
        _aiConvList = [];
      } else {
        _aiConvList = res.data || [];
      }
      // Open last conversation or create new one
      if (_aiConvList.length > 0) {
        _aiSwitchConversation(_aiConvList[0].id);
      } else {
        _aiNewConversation();
      }
    });
}

// ─── Get current user ID ───

function _aiGetUserId() {
  try {
    var s = window.supabase.auth.session && window.supabase.auth.session();
    if (s && s.user) return s.user.id;
  } catch (e) { /* ignore */ }
  try {
    // supabase-js v2
    var d = window.supabase.auth.getUser();
    if (d && d.then) return null; // async, handled below
  } catch (e2) { /* ignore */ }
  return null;
}

function _aiGetUserIdAsync(callback) {
  if (!window.supabase) { callback(null); return; }
  // Try sync first
  var sync = _aiGetUserId();
  if (sync) { callback(sync); return; }
  // v2 async
  window.supabase.auth.getUser().then(function(res) {
    callback(res.data && res.data.user ? res.data.user.id : null);
  }).catch(function() { callback(null); });
}

// ─── Create new conversation ───

function _aiNewConversation() {
  _aiGetUserIdAsync(function(uid) {
    if (!uid || !window.supabase) {
      _aiShowOffline(); return;
    }
    var newId = _aiGenUUID();
    var row = {
      id: newId,
      user_id: uid,
      title: 'Nová konverzace',
      messages: [],
      booking_id: _aiAgentBookingId || null
    };
    window.supabase
      .from('ai_customer_conversations')
      .insert(row)
      .select('id, title, booking_id, created_at, updated_at')
      .then(function(res) {
        if (res.error) {
          console.warn('[AI-CONV] create error:', res.error);
          // Fallback: work offline with temp conv
          _aiActiveConvId = newId;
          _aiActiveConv = { id: newId, title: 'Nová konverzace', messages: [], booking_id: _aiAgentBookingId };
          _aiConvList.unshift({ id: newId, title: 'Nová konverzace', created_at: new Date().toISOString(), updated_at: new Date().toISOString() });
        } else {
          var created = (res.data && res.data[0]) || row;
          _aiActiveConvId = created.id;
          _aiActiveConv = { id: created.id, title: created.title, messages: [], booking_id: _aiAgentBookingId };
          _aiConvList.unshift(created);
        }
        _aiConvListOpen = false;
        _aiRenderChat();
        _aiRenderWelcome();
      });
  });
}

function aiAgentNewConversation() {
  _aiNewConversation();
}

// ─── Switch conversation ───

function _aiSwitchConversation(convId) {
  if (!window.supabase) { _aiShowOffline(); return; }
  _aiActiveConvId = convId;
  _aiConvListOpen = false;
  window.supabase
    .from('ai_customer_conversations')
    .select('id, title, messages, booking_id, created_at, updated_at')
    .eq('id', convId)
    .limit(1)
    .then(function(res) {
      if (res.error || !res.data || res.data.length === 0) {
        console.warn('[AI-CONV] switch error:', res.error);
        _aiNewConversation();
        return;
      }
      _aiActiveConv = res.data[0];
      if (!Array.isArray(_aiActiveConv.messages)) _aiActiveConv.messages = [];
      _aiRenderChat();
      if (_aiActiveConv.messages.length === 0) {
        _aiRenderWelcome();
      } else {
        _aiRenderMessages();
      }
    });
}

function aiAgentSwitchConversation(convId) {
  _aiSwitchConversation(convId);
}

// ─── Delete conversation ───

function aiAgentDeleteConversation(convId, evt) {
  if (evt) { evt.stopPropagation(); evt.preventDefault(); }
  if (!window.supabase) return;
  window.supabase
    .from('ai_customer_conversations')
    .delete()
    .eq('id', convId)
    .then(function(res) {
      if (res.error) {
        console.warn('[AI-CONV] delete error:', res.error);
        return;
      }
      _aiConvList = _aiConvList.filter(function(c) { return c.id !== convId; });
      if (_aiActiveConvId === convId) {
        if (_aiConvList.length > 0) {
          _aiSwitchConversation(_aiConvList[0].id);
        } else {
          _aiNewConversation();
        }
      } else {
        _aiRenderConvList();
      }
    });
}

// ─── Save messages to Supabase ───

function _aiSaveMessages(optTitle) {
  if (!window.supabase || !_aiActiveConvId || !_aiActiveConv) return;
  var update = {
    messages: _aiActiveConv.messages,
    updated_at: new Date().toISOString()
  };
  if (optTitle) update.title = optTitle;
  window.supabase
    .from('ai_customer_conversations')
    .update(update)
    .eq('id', _aiActiveConvId)
    .then(function(res) {
      if (res.error) console.warn('[AI-CONV] save error:', res.error);
      // Update list item title if changed
      if (optTitle) {
        for (var i = 0; i < _aiConvList.length; i++) {
          if (_aiConvList[i].id === _aiActiveConvId) {
            _aiConvList[i].title = optTitle;
            _aiConvList[i].updated_at = update.updated_at;
            break;
          }
        }
      }
    });
}

// ─── Render: chat area ───

function _aiRenderChat() {
  var msgs = document.getElementById('ai-agent-msgs');
  if (msgs) msgs.innerHTML = '';
  var inp = document.getElementById('ai-agent-input');
  if (inp) inp.value = '';
  _updateAiAgentSosBtn(false);
  _renderAiPhotoPreview();
  _aiRenderConvList();
}

function _aiRenderWelcome() {
  var msgs = document.getElementById('ai-agent-msgs');
  if (!msgs) return;
  msgs.innerHTML =
    '<div class="ai-msg bot"><div class="ai-bubble">' +
    '\ud83d\udc4b Ahoj! Jsem AI servisn\u00ed technik MotoGo24.<br><br>' +
    'M\u00e1m p\u0159ehled o va\u0161ich rezervac\u00edch i n\u00e1vody k motork\u00e1m. Pomohu v\u00e1m s:<br>' +
    '\ud83d\udd0d Diagnostika z\u00e1vady<br>' +
    '\ud83d\udee0\ufe0f \u0158e\u0161en\u00ed na m\u00edst\u011b<br>' +
    '\ud83d\udcd6 N\u00e1vod k obsluze a funkce motorky<br><br>' +
    '<strong>\ud83d\udcf8 Tip:</strong> Vyfo\u0165te kontrolky na bud\u00edku \u2014 pomohou mi p\u0159esn\u011bji diagnostikovat probl\u00e9m.<br><br>' +
    '<em>Nap\u0159.: "Sv\u00edt\u00ed kontrolka motoru", "Jak p\u0159epnu j\u00edzdn\u00ed m\u00f3d?"</em></div></div>';
}

function _aiRenderMessages() {
  var msgs = document.getElementById('ai-agent-msgs');
  if (!msgs || !_aiActiveConv) return;
  var html = '';
  var messages = _aiActiveConv.messages;
  for (var i = 0; i < messages.length; i++) {
    var m = messages[i];
    var cls = m.role === 'user' ? 'user' : 'bot';
    var text = (m.content || '').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');
    html += '<div class="ai-msg ' + cls + '"><div class="ai-bubble">' + text + '</div></div>';
  }
  msgs.innerHTML = html;
  msgs.scrollTop = msgs.scrollHeight;
}

// ─── Render: conversation list overlay ───

function _aiToggleConvList() {
  _aiConvListOpen = !_aiConvListOpen;
  _aiRenderConvList();
}

function _aiRenderConvList() {
  var overlay = document.getElementById('ai-conv-list-overlay');
  if (!overlay) return;
  if (!_aiConvListOpen) {
    overlay.style.display = 'none';
    return;
  }
  overlay.style.display = 'block';
  var html = '<div style="padding:12px 16px;border-bottom:1px solid var(--g200);display:flex;align-items:center;justify-content:space-between;">' +
    '<span style="font-size:15px;font-weight:800;color:var(--dark);">Konverzace</span>' +
    '<button onclick="_aiToggleConvList()" style="background:none;border:none;font-size:20px;cursor:pointer;color:var(--g400);padding:4px;">\u2715</button></div>';
  if (_aiConvList.length === 0) {
    html += '<div style="padding:24px 16px;text-align:center;color:var(--g400);font-size:13px;">\u017d\u00e1dn\u00e9 konverzace</div>';
  } else {
    html += '<div style="max-height:55vh;overflow-y:auto;">';
    for (var i = 0; i < _aiConvList.length; i++) {
      var c = _aiConvList[i];
      var isActive = c.id === _aiActiveConvId;
      var bg = isActive ? 'background:rgba(116,251,113,0.15);border-left:3px solid var(--green);' : 'border-left:3px solid transparent;';
      var dateStr = '';
      try {
        var d = new Date(c.updated_at || c.created_at);
        dateStr = d.toLocaleDateString('cs-CZ') + ' ' + d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' });
      } catch (e) { dateStr = ''; }
      var title = (c.title || 'Konverzace').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      html += '<div onclick="aiAgentSwitchConversation(\'' + c.id + '\')" ' +
        'style="padding:12px 16px;cursor:pointer;' + bg + 'display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--g200);">' +
        '<div style="flex:1;min-width:0;overflow:hidden;">' +
        '<div style="font-size:13px;font-weight:700;color:var(--dark);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' + title + '</div>' +
        '<div style="font-size:10px;color:var(--g400);margin-top:2px;">' + dateStr + '</div></div>' +
        '<button onclick="aiAgentDeleteConversation(\'' + c.id + '\', event)" ' +
        'style="flex-shrink:0;margin-left:8px;width:28px;height:28px;background:none;border:1px solid var(--g200);border-radius:var(--rsm);cursor:pointer;font-size:13px;color:var(--red);display:flex;align-items:center;justify-content:center;">\u2715</button>' +
        '</div>';
    }
    html += '</div>';
  }
  overlay.innerHTML = html;
}

// ─── Offline message ───

function _aiShowOffline() {
  var msgs = document.getElementById('ai-agent-msgs');
  if (msgs) {
    msgs.innerHTML =
      '<div class="ai-msg bot"><div class="ai-bubble">' +
      '\u26a0\ufe0f Nen\u00ed p\u0159ipojen\u00ed k internetu. AI technik vy\u017eaduje p\u0159ipojen\u00ed.<br><br>' +
      'Zavolejte p\u0159\u00edmo: <strong>+420 774 256 271</strong></div></div>';
  }
}

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

// ─── Send message ───

function aiAgentSend() {
  if (_aiAgentSending) return;
  var inp = document.getElementById('ai-agent-input');
  var txt = (inp ? inp.value : '').trim();
  var hasPhotos = _aiAgentPhotos.length > 0;
  if (!txt && !hasPhotos) return;
  var msgs = document.getElementById('ai-agent-msgs');
  if (!msgs) return;
  if (!_aiActiveConv) return;

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
  else if (hasPhotos) userHtml += '<em>\ud83d\udcf8 Fotka kontrolek</em>';
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
  var msgText = txt || 'Pod\u00edvej se na fotku kontrolek/bud\u00edku a \u0159ekni mi co to znamen\u00e1.';

  // Save user message to conversation
  _aiActiveConv.messages.push({ role: 'user', content: msgText });

  // Auto-title from first user message
  var newTitle = null;
  var userMsgCount = 0;
  for (var k = 0; k < _aiActiveConv.messages.length; k++) {
    if (_aiActiveConv.messages[k].role === 'user') userMsgCount++;
  }
  if (userMsgCount === 1) {
    newTitle = msgText.substring(0, 40);
    if (msgText.length > 40) newTitle += '\u2026';
    _aiActiveConv.title = newTitle;
  }
  _aiSaveMessages(newTitle);

  _aiAgentPhotos = [];
  _renderAiPhotoPreview();
  _aiAgentSending = true;

  // Show typing indicator
  var typId = 'ai-agent-typ-' + Date.now();
  msgs.innerHTML += '<div class="ai-msg bot" id="' + typId + '">' +
    '<div class="ai-bubble" style="color:var(--g400);">\u23f3 Analyzuji' + (images.length ? ' fotky' : '') + '...</div></div>';
  msgs.scrollTop = msgs.scrollHeight;

  var btn = document.getElementById('ai-agent-send-btn');
  if (btn) { btn.disabled = true; btn.textContent = '\u23f3'; }

  // Build full conversation history (no limit)
  var convHistory = [];
  for (var h = 0; h < _aiActiveConv.messages.length - 1; h++) {
    convHistory.push(_aiActiveConv.messages[h]);
  }

  var body = {
    message: msgText,
    booking_id: _aiActiveConv.booking_id || _aiAgentBookingId,
    conversation_history: convHistory
  };
  if (images.length > 0) body.images = images;

  if (!window.supabase) {
    _aiHandleSendError(typId, btn, msgs);
    return;
  }

  window.supabase.functions.invoke('ai-moto-agent', { body: body })
    .then(function(r) {
      if (r.error) throw r.error;
      var data = r.data || {};
      var reply = data.reply || 'Odpov\u011b\u010f nedostupn\u00e1. Zkuste to znovu.';

      // Save assistant message
      _aiActiveConv.messages.push({ role: 'assistant', content: reply });
      _aiSaveMessages(null);

      var typEl = document.getElementById(typId);
      if (typEl) {
        typEl.querySelector('.ai-bubble').innerHTML =
          reply.replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');
      }
      _updateAiAgentSosBtn(data.suggest_sos === true);
      _aiAgentSending = false;
      if (btn) { btn.disabled = false; btn.textContent = '\u27a4'; }
      if (msgs) msgs.scrollTop = msgs.scrollHeight;
    })
    .catch(function(e) {
      console.warn('[AI-AGENT]', e);
      _aiHandleSendError(typId, btn, msgs);
    });
}

function _aiHandleSendError(typId, btn, msgs) {
  _aiAgentSending = false;
  var typEl = document.getElementById(typId);
  if (typEl) {
    typEl.querySelector('.ai-bubble').innerHTML =
      '\u274c Nepoda\u0159ilo se spojit s AI asistentem. Zkuste to znovu nebo zavolejte +420 774 256 271.';
  }
  if (btn) { btn.disabled = false; btn.textContent = '\u27a4'; }
  if (msgs) msgs.scrollTop = msgs.scrollHeight;
}

// ─── SOS button ───

function _updateAiAgentSosBtn(show) {
  var el = document.getElementById('ai-agent-sos-wrap');
  if (el) el.style.display = show ? 'block' : 'none';
}

// ─── Template for s-ai-agent screen ───

Templates['s-ai-agent'] = [
  '<div class="sos-sub-hdr" style="background:linear-gradient(135deg,#1a2e22,#2d5a3c);">',
  '<div style="display:flex;align-items:center;justify-content:space-between;width:100%;padding:0 4px;">',
  '<div class="sos-sub-back" onclick="histBack()" style="margin:0;"><div class="sos-sub-back-btn">\u2190</div>',
  '<div style="color:rgba(255,255,255,.7);font-size:13px;font-weight:600;">Zp\u011bt</div></div>',
  '<div style="display:flex;gap:8px;">',
  '<button onclick="_aiToggleConvList()" style="background:rgba(255,255,255,.15);border:none;border-radius:var(--rsm);padding:8px 10px;cursor:pointer;font-size:15px;color:#fff;" title="Seznam konverzac\u00ed">\ud83d\udccb</button>',
  '<button onclick="aiAgentNewConversation()" style="background:rgba(116,251,113,.25);border:1px solid rgba(116,251,113,.4);border-radius:var(--rsm);padding:8px 12px;cursor:pointer;font-size:15px;color:var(--green);font-weight:900;" title="Nov\u00e1 konverzace">+</button>',
  '</div></div>',
  '<div style="font-size:28px;margin-bottom:8px;">\ud83e\udd16</div>',
  '<h2 style="color:#fff;font-size:20px;font-weight:900;">AI Servisn\u00ed technik</h2>',
  '<p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Diagnostika z\u00e1vad va\u0161\u00ed motorky \u2022 fotky kontrolek</p>',
  '</div>',
  '<div style="position:relative;">',
  '<div id="ai-conv-list-overlay" style="display:none;position:absolute;top:0;left:0;right:0;z-index:50;background:#fff;border-bottom:2px solid var(--green);border-radius:0 0 var(--r) var(--r);box-shadow:var(--shadow);max-height:70vh;overflow:hidden;"></div>',
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
  'align-items:center;justify-content:center;" title="Vyfotit kontrolky">\ud83d\udcf7</button>',
  '<input type="text" id="ai-agent-input" placeholder="Popi\u0161te probl\u00e9m nebo po\u0161lete fotku..." ',
  'onkeydown="if(event.key===\'Enter\')aiAgentSend()" style="min-width:0;">',
  '<button id="ai-agent-send-btn" onclick="aiAgentSend()" ',
  'style="white-space:nowrap;flex-shrink:0;padding:10px 12px;">\u27a4</button>',
  '</div></div>'
].join('');
