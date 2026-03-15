// ===== MESSAGES-UI.JS – Admin messages + Chat threads =====
// Handles rendering messages screen, badge counts, notifications, and chat.

var _currentThreadId = null;
var _msgActiveTab = 'notif';
var _msgAllNotifs = null;

// ===== TAB SWITCHING =====
function msgSwitchTab(tab){
  _msgActiveTab = tab;
  var notifList = document.getElementById('messages-list');
  var threadsList = document.getElementById('threads-list');
  var tabNotif = document.getElementById('msg-tab-notif');
  var tabChat = document.getElementById('msg-tab-chat');
  if(!notifList || !threadsList) return;

  if(tab === 'chat'){
    notifList.style.display = 'none';
    threadsList.style.display = '';
    if(tabNotif){ tabNotif.style.background = '#fff'; tabNotif.style.color = 'var(--black)'; tabNotif.style.borderColor = 'var(--g200)'; }
    if(tabChat){ tabChat.style.background = 'var(--green)'; tabChat.style.color = '#fff'; tabChat.style.borderColor = 'var(--green)'; }
    renderThreadsList();
  } else {
    notifList.style.display = '';
    threadsList.style.display = 'none';
    if(tabNotif){ tabNotif.style.background = 'var(--green)'; tabNotif.style.color = '#fff'; tabNotif.style.borderColor = 'var(--green)'; }
    if(tabChat){ tabChat.style.background = '#fff'; tabChat.style.color = 'var(--black)'; tabChat.style.borderColor = 'var(--g200)'; }
  }
}

// ===== RENDER NOTIFICATIONS (admin_messages) =====
async function renderAdminMessages(){
  var wrap = document.getElementById('messages-list');
  if(!wrap) return;
  wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1n\u00ed...</div>';

  try {
    _msgAllNotifs = await apiFetchAdminMessages();
    _msgRenderFiltered();
  } catch(e){
    console.error('renderAdminMessages error:', e);
    wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--red);">Chyba p\u0159i na\u010d\u00edt\u00e1n\u00ed zpr\u00e1v</div>';
  }
}

function msgApplyFilter(){
  if(_msgActiveTab === 'notif') _msgRenderFiltered();
}

function _msgRenderFiltered(){
  var wrap = document.getElementById('messages-list');
  if(!wrap) return;
  var msgs = (_msgAllNotifs || []).slice();

  // Apply type filter
  var typeF = (document.getElementById('msg-type-filter') || {}).value || '';
  if(typeF) msgs = msgs.filter(function(m){ return m.type === typeF; });

  // Apply sort
  var sortV = (document.getElementById('msg-sort') || {}).value || 'date_desc';
  var asc = sortV === 'date_asc';
  msgs.sort(function(a, b){
    var da = new Date(a.created_at || 0), db = new Date(b.created_at || 0);
    return asc ? da - db : db - da;
  });

  if(msgs.length === 0){
    wrap.innerHTML = '<div style="text-align:center;padding:40px 20px;">' +
      '<div style="font-size:48px;margin-bottom:12px;">\ud83d\udce8</div>' +
      '<div style="font-size:14px;font-weight:700;color:var(--black);margin-bottom:4px;">\u017d\u00e1dn\u00e9 ozn\u00e1men\u00ed</div>' +
      '<div style="font-size:12px;color:var(--g400);line-height:1.5;">Zat\u00edm nem\u00e1te \u017e\u00e1dn\u00e9 ozn\u00e1men\u00ed z MotoGo24.</div>' +
      '</div>';
    return;
  }

  var html = '';
  msgs.forEach(function(m){
    var date = m.created_at ? new Date(m.created_at) : new Date();
    var fmt = date.toLocaleDateString('cs-CZ') + ' ' +
      date.toLocaleTimeString('cs-CZ', {hour:'2-digit', minute:'2-digit'});
    var isUnread = !m.read;
    var icon = _msgIcon(m.type);

    html += '<div class="msg-item' + (isUnread ? ' msg-unread' : '') + '"' +
      ' onclick="markMsgRead(\'' + m.id + '\',this)">' +
      '<div class="msg-icon-wrap"><div class="msg-icon">' + icon + '</div>' +
      (isUnread ? '<div class="msg-dot"></div>' : '') + '</div>' +
      '<div class="msg-body">' +
      '<div class="msg-title">' + _escHtml(m.title || 'Zpr\u00e1va z Moto Go') + '</div>' +
      '<div class="msg-text">' + _escHtml(m.message || '') + '</div>' +
      '<div class="msg-time">' + fmt + '</div>' +
      '</div></div>';
  });
  wrap.innerHTML = html;
}

// ===== RENDER THREADS LIST =====
async function renderThreadsList(){
  var wrap = document.getElementById('threads-list');
  if(!wrap) return;
  wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1n\u00ed...</div>';

  try {
    var threads = await apiFetchMyThreads();
    var html = '';

    // "New message" button
    html += '<div onclick="startNewThread()" style="background:var(--green);color:#fff;border-radius:var(--r);padding:14px 16px;margin-bottom:12px;cursor:pointer;display:flex;align-items:center;gap:10px;">' +
      '<div style="font-size:20px;">✍️</div>' +
      '<div><div style="font-size:13px;font-weight:800;">Nov\u00e1 zpr\u00e1va</div>' +
      '<div style="font-size:11px;opacity:.8;">Napsat MotoGo24</div></div>' +
      '<div style="margin-left:auto;font-size:18px;">›</div></div>';

    if(!threads || threads.length === 0){
      html += '<div style="text-align:center;padding:30px 20px;">' +
        '<div style="font-size:36px;margin-bottom:8px;">💬</div>' +
        '<div style="font-size:13px;font-weight:700;color:var(--black);">\u017d\u00e1dn\u00e9 konverzace</div>' +
        '<div style="font-size:12px;color:var(--g400);margin-top:4px;">Za\u010dn\u011bte konverzaci s MotoGo24</div>' +
        '</div>';
      wrap.innerHTML = html;
      return;
    }

    threads.forEach(function(t){
      var msgs = t.messages || [];
      var lastMsg = msgs.length > 0 ? msgs[msgs.length - 1] : null;
      var unread = msgs.filter(function(m){ return m.direction === 'admin' && !m.read_at; }).length;
      var date = t.last_message_at ? new Date(t.last_message_at) : new Date(t.created_at);
      var fmt = date.toLocaleDateString('cs-CZ') + ' ' + date.toLocaleTimeString('cs-CZ', {hour:'2-digit', minute:'2-digit'});
      var isSOS = t.subject && t.subject.indexOf('SOS:') === 0;
      var icon = isSOS ? '\ud83d\ude91' : '\ud83d\udcac';
      var preview = lastMsg ? (lastMsg.content || '').slice(0, 60) : '';
      if(preview.length >= 60) preview += '...';
      var dirIcon = lastMsg && lastMsg.direction === 'customer' ? 'Vy: ' : '';

      html += '<div onclick="openThread(\'' + t.id + '\')" style="background:#fff;border-radius:var(--r);padding:14px 16px;margin-bottom:8px;cursor:pointer;box-shadow:var(--shadow);display:flex;align-items:center;gap:12px;' +
        (unread > 0 ? 'border-left:4px solid var(--green);' : '') + '">' +
        '<div style="font-size:24px;flex-shrink:0;">' + icon + '</div>' +
        '<div style="flex:1;min-width:0;">' +
        '<div style="display:flex;justify-content:space-between;align-items:center;">' +
        '<div style="font-size:13px;font-weight:800;color:var(--black);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:70%;">' + _escHtml(t.subject || 'Konverzace') + '</div>' +
        (unread > 0 ? '<div style="background:var(--green);color:#fff;border-radius:50%;min-width:20px;height:20px;display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:800;">' + unread + '</div>' : '') +
        '</div>' +
        '<div style="font-size:12px;color:var(--g400);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px;">' + dirIcon + _escHtml(preview) + '</div>' +
        '<div style="font-size:10px;color:var(--g300);margin-top:3px;">' + fmt + '</div>' +
        '</div></div>';
    });

    wrap.innerHTML = html;
  } catch(e){
    console.error('renderThreadsList error:', e);
    wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--red);">Chyba</div>';
  }
}

// ===== OPEN THREAD CHAT =====
function openThread(threadId){
  _currentThreadId = threadId;
  goTo('s-messages-thread');
}

async function renderThreadChat(){
  if(!_currentThreadId) return;
  var msgsWrap = document.getElementById('thread-messages');
  var titleEl = document.getElementById('thread-title');
  var statusEl = document.getElementById('thread-status');
  if(!msgsWrap) return;

  msgsWrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);">\u23f3</div>';

  try {
    var threads = await apiFetchMyThreads();
    var thread = null;
    for(var i = 0; i < threads.length; i++){
      if(threads[i].id === _currentThreadId){ thread = threads[i]; break; }
    }
    if(!thread){
      msgsWrap.innerHTML = '<div style="text-align:center;padding:20px;">Konverzace nenalezena</div>';
      return;
    }

    if(titleEl) titleEl.textContent = thread.subject || 'Konverzace';
    if(statusEl) statusEl.textContent = thread.status === 'closed' ? 'Uzavřeno' : 'Aktivní';

    var msgs = (thread.messages || []).sort(function(a,b){
      return new Date(a.created_at) - new Date(b.created_at);
    });

    if(msgs.length === 0){
      msgsWrap.innerHTML = '<div style="text-align:center;padding:40px 20px;color:var(--g400);font-size:13px;">Zat\u00edm \u017e\u00e1dn\u00e9 zpr\u00e1vy</div>';
      _toggleReplyBar(thread.status !== 'closed');
      return;
    }

    var html = '';
    msgs.forEach(function(m){
      var isMe = m.direction === 'customer';
      var date = new Date(m.created_at);
      var fmt = date.toLocaleTimeString('cs-CZ', {hour:'2-digit', minute:'2-digit'});
      var dayFmt = date.toLocaleDateString('cs-CZ');

      html += '<div style="display:flex;' + (isMe ? 'justify-content:flex-end;' : 'justify-content:flex-start;') + 'margin-bottom:8px;">' +
        '<div style="max-width:80%;padding:10px 14px;border-radius:' + (isMe ? '16px 16px 4px 16px' : '16px 16px 16px 4px') + ';' +
        'background:' + (isMe ? 'var(--green)' : '#fff') + ';color:' + (isMe ? '#fff' : 'var(--black)') + ';' +
        'box-shadow:0 1px 3px rgba(0,0,0,.08);font-size:13px;line-height:1.5;">' +
        '<div>' + _escHtml(m.content || '') + '</div>' +
        '<div style="font-size:10px;opacity:.6;margin-top:4px;text-align:right;">' + dayFmt + ' ' + fmt + '</div>' +
        '</div></div>';
    });

    msgsWrap.innerHTML = html;
    msgsWrap.scrollTop = msgsWrap.scrollHeight;
    _toggleReplyBar(thread.status !== 'closed');

    // Mark admin messages as read
    msgs.forEach(function(m){
      if(m.direction === 'admin' && !m.read_at && window.supabase){
        window.supabase.from('messages').update({read_at: new Date().toISOString()}).eq('id', m.id).then(function(){});
      }
    });
  } catch(e){
    console.error('renderThreadChat error:', e);
    msgsWrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--red);">Chyba</div>';
  }
}

function _toggleReplyBar(show){
  var bar = document.getElementById('thread-reply-bar');
  if(bar) bar.style.display = show ? 'flex' : 'none';
}

// ===== SEND REPLY =====
async function sendThreadReply(){
  var input = document.getElementById('thread-reply-input');
  if(!input || !input.value.trim() || !_currentThreadId) return;
  var content = input.value.trim();
  input.value = '';
  input.disabled = true;

  var result = await apiSendCustomerMessage(_currentThreadId, content);
  input.disabled = false;

  if(result && result.error){
    showT('\u274c', 'Chyba', result.error);
    input.value = content;
    return;
  }

  // Re-render chat
  renderThreadChat();
}

// ===== START NEW THREAD =====
async function startNewThread(){
  var subject = prompt('Předmět zprávy:');
  if(!subject || !subject.trim()) return;
  var message = prompt('Vaše zpráva:');
  if(!message || !message.trim()) return;

  try {
    var uid = await _getUserId();
    if(!uid){ showT('\u274c', 'Nepřihlášen', ''); return; }
    var profile = await apiFetchProfile();
    var senderName = profile ? profile.full_name : 'Zákazník';

    var r = await window.supabase.from('message_threads').insert({
      customer_id: uid,
      channel: 'app',
      status: 'open',
      subject: subject.trim(),
      last_message_at: new Date().toISOString()
    }).select().single();

    if(r.error){ showT('\u274c', 'Chyba', r.error.message); return; }
    var thread = r.data;

    await window.supabase.from('messages').insert({
      thread_id: thread.id,
      direction: 'customer',
      sender_name: senderName,
      content: message.trim()
    });

    _currentThreadId = thread.id;
    goTo('s-messages-thread');
  } catch(e){
    console.error('startNewThread error:', e);
    showT('\u274c', 'Chyba', 'Nepodařilo se vytvořit konverzaci');
  }
}

// ===== HELPERS =====
function _msgIcon(type){
  var icons = {
    sos_response: '\ud83d\ude91',
    sos_auto: '\ud83d\ude91',
    accident_response: '\u26a0\ufe0f',
    replacement: '\ud83d\udee0\ufe0f',
    tow: '\ud83d\ude9a',
    info: '\u2139\ufe0f',
    thanks: '\ud83d\ude4f'
  };
  return icons[type] || '\ud83d\udce9';
}

function _escHtml(s){
  var d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

// ===== MARK MESSAGE AS READ =====
function markMsgRead(msgId, el){
  if(el) el.classList.remove('msg-unread');
  var dot = el ? el.querySelector('.msg-dot') : null;
  if(dot) dot.remove();
  if(typeof apiMarkMessageRead === 'function'){
    apiMarkMessageRead(msgId);
  }
  updateMsgBadge();
}

// ===== UPDATE UNREAD BADGE =====
function updateMsgBadge(){
  if(typeof apiGetUnreadMessageCount !== 'function') return;
  apiGetUnreadMessageCount().then(function(count){
    var badge = document.getElementById('msg-badge');
    if(badge){
      if(count > 0){
        badge.textContent = count > 99 ? '99+' : count;
        badge.style.display = '';
      } else {
        badge.style.display = 'none';
      }
    }
  });
}

// ===== FULL-SCREEN MESSAGE OVERLAY =====
function showFullScreenMessage(title, body, icon){
  var existing = document.getElementById('mg-fullscreen-msg');
  if(existing) existing.remove();
  var ov = document.createElement('div');
  ov.id = 'mg-fullscreen-msg';
  ov.style.cssText = 'position:fixed;inset:0;z-index:9999;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;padding:20px;backdrop-filter:blur(4px);';
  ov.innerHTML = '<div style="background:#fff;border-radius:20px;padding:28px 24px;max-width:340px;width:100%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.3);">' +
    '<div style="font-size:48px;margin-bottom:12px;">' + (icon || '\ud83d\udce9') + '</div>' +
    '<div style="font-size:18px;font-weight:900;color:#0f1a14;margin-bottom:10px;">' + _escHtml(title || 'Zpr\u00e1va z Moto Go') + '</div>' +
    '<div style="font-size:14px;color:#4a6357;line-height:1.6;margin-bottom:20px;font-weight:500;">' + _escHtml(body || '') + '</div>' +
    '<button onclick="document.getElementById(\'mg-fullscreen-msg\').remove()" style="width:100%;padding:14px;background:#74FB71;color:#fff;border:none;border-radius:50px;font-family:var(--font,Montserrat,sans-serif);font-size:14px;font-weight:800;cursor:pointer;text-transform:uppercase;letter-spacing:.5px;">Rozum\u00edm</button>' +
    '</div>';
  document.body.appendChild(ov);
}

// ===== IN-APP NOTIFICATION BANNER =====
function showMsgNotification(msg){
  var title = msg.title || 'Zpr\u00e1va z Moto Go';
  var body = msg.message || '';
  var icon = _msgIcon(msg.type);

  // Full-screen overlay (user must confirm)
  showFullScreenMessage(title, body, icon);

  // Also show toast
  if(typeof showT === 'function'){
    showT('\ud83d\udce9', title, body);
  }
  updateMsgBadge();

  // Native notification (Cordova local notification)
  if(window.cordova && window.cordova.plugins &&
     window.cordova.plugins.notification &&
     window.cordova.plugins.notification.local){
    window.cordova.plugins.notification.local.schedule({
      id: Date.now(),
      title: title,
      text: body,
      icon: 'res://icon',
      smallIcon: 'res://icon',
      foreground: true,
      lockscreen: true
    });
  }
}

// ===== SUBSCRIBE TO REALTIME MESSAGES =====
function initAdminMessageSubscription(){
  if(typeof apiSubscribeAdminMessages !== 'function') return;
  apiSubscribeAdminMessages(function(newMsg){
    showMsgNotification(newMsg);
  });
  // Initial badge update
  updateMsgBadge();
}
