// ===== AI-AGENT-SEND.JS – Send message, error handling, SOS button & template =====
// Split from ai-agent-ui.js. Depends on: ai-agent-ui.js (state + CRUD), ai-agent-photos.js

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
