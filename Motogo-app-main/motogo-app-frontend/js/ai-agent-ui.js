// ===== AI-AGENT-UI.JS – Init, load, UUID, conversations CRUD & render =====
// Diagnostika závad motorek přes AI (Anthropic Claude via Edge Function ai-moto-agent)
// Split: ai-agent-photos.js (fotky), ai-agent-send.js (odesílání, SOS, template)
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
  _aiGetUserIdAsync(function(uid) {
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
          // Fallback: work without persistence (table may not exist)
          _aiConvList = [];
          _aiFallbackNewConv();
          return;
        }
        _aiConvList = res.data || [];
        // Open last conversation or create new one
        if (_aiConvList.length > 0) {
          _aiSwitchConversation(_aiConvList[0].id);
        } else {
          _aiNewConversation();
        }
      });
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

// ─── Fallback: local-only conversation (no DB table) ───

function _aiFallbackNewConv() {
  var newId = _aiGenUUID();
  _aiActiveConvId = newId;
  _aiActiveConv = { id: newId, title: 'Nová konverzace', messages: [], booking_id: _aiAgentBookingId };
  _aiConvList = [{ id: newId, title: 'Nová konverzace', created_at: new Date().toISOString(), updated_at: new Date().toISOString() }];
  _aiConvListOpen = false;
  _aiRenderChat();
  _aiRenderWelcome();
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
