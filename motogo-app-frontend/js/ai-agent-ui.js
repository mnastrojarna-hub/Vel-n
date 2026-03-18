// ===== AI-AGENT-UI.JS – AI Servisní agent chat pro zákazníky =====
// Diagnostika závad motorek přes AI (Anthropic Claude via Edge Function ai-moto-agent)
// Max 5000 tokenů (VoltBuilder limit)

var _aiAgentHistory = [];
var _aiAgentSending = false;
var _aiAgentBookingId = null;

function aiAgentOpen(bookingId) {
  _aiAgentHistory = [];
  _aiAgentSending = false;
  _aiAgentBookingId = bookingId || _sosCurrentBookingId || null;
  goTo('s-ai-agent');
  setTimeout(function() {
    var msgs = document.getElementById('ai-agent-msgs');
    if (msgs) msgs.innerHTML =
      '<div class="ai-msg bot"><div class="ai-bubble">' +
      '👋 Ahoj! Jsem AI servisní technik MotoGo24.<br><br>' +
      'Popište mi problém s vaší motorkou a pomohu vám:<br>' +
      '🔍 Diagnostikovat závadu<br>' +
      '✅ Rozhodnout jestli můžete jet dál<br>' +
      '🛠️ Doporučit řešení na místě<br><br>' +
      '<em>Např.: "Svítí kontrolka motoru", "Motorka špatně startuje"</em></div></div>';
    var inp = document.getElementById('ai-agent-input');
    if (inp) inp.value = '';
    _updateAiAgentSosBtn(false);
  }, 80);
}

async function aiAgentSend() {
  if (_aiAgentSending) return;
  var inp = document.getElementById('ai-agent-input');
  var txt = (inp ? inp.value : '').trim();
  if (!txt) return;
  var msgs = document.getElementById('ai-agent-msgs');
  if (!msgs) return;

  // Show user message
  msgs.innerHTML += '<div class="ai-msg user"><div class="ai-bubble">' +
    txt.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</div></div>';
  if (inp) inp.value = '';
  msgs.scrollTop = msgs.scrollHeight;

  _aiAgentHistory.push({ role: 'user', content: txt });
  _aiAgentSending = true;

  // Show typing
  var typId = 'ai-agent-typ-' + Date.now();
  msgs.innerHTML += '<div class="ai-msg bot" id="' + typId + '">' +
    '<div class="ai-bubble" style="color:var(--g400);">⏳ Analyzuji...</div></div>';
  msgs.scrollTop = msgs.scrollHeight;

  // Update send button
  var btn = document.getElementById('ai-agent-send-btn');
  if (btn) { btn.disabled = true; btn.textContent = '⏳'; }

  try {
    if (!window.supabase) throw new Error('No connection');
    var r = await window.supabase.functions.invoke('ai-moto-agent', {
      body: {
        message: txt,
        booking_id: _aiAgentBookingId,
        conversation_history: _aiAgentHistory.slice(-10)
      }
    });

    if (r.error) throw r.error;
    var data = r.data || {};
    var reply = data.reply || 'Odpověď nedostupná. Zkuste to znovu.';
    var suggestSos = data.suggest_sos === true;

    _aiAgentHistory.push({ role: 'assistant', content: reply });

    var typEl = document.getElementById(typId);
    if (typEl) {
      typEl.querySelector('.ai-bubble').innerHTML =
        reply.replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');
    }

    _updateAiAgentSosBtn(suggestSos);
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
  '<p style="color:rgba(255,255,255,.7);font-size:12px;margin-top:4px;">Diagnostika z\u00e1vad va\u0161\u00ed motorky</p>',
  '</div>',
  '<div class="ai-chat-wrap" style="margin-top:0;">',
  '<div class="ai-chat-msgs" id="ai-agent-msgs" style="min-height:250px;max-height:50vh;"></div>',
  '<div id="ai-agent-sos-wrap" style="display:none;padding:8px 12px;">',
  '<button onclick="goTo(\'s-sos\')" style="width:100%;background:#b91c1c;color:#fff;border:none;',
  'border-radius:50px;padding:12px;font-family:var(--font);font-size:13px;font-weight:800;cursor:pointer;">',
  '\ud83c\udd98 P\u0159ej\u00edt na SOS</button></div>',
  '<div class="ai-chat-input">',
  '<input type="text" id="ai-agent-input" placeholder="Popi\u0161te probl\u00e9m..." ',
  'onkeydown="if(event.key===\'Enter\')aiAgentSend()" style="min-width:0;">',
  '<button id="ai-agent-send-btn" onclick="aiAgentSend()" ',
  'style="white-space:nowrap;flex-shrink:0;padding:10px 12px;">➤</button>',
  '</div></div>'
].join('');
