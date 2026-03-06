// ===== MESSAGES-UI.JS – Admin messages (Zprávy z Moto Go) =====
// Handles rendering messages screen, badge counts, and notifications.

// ===== RENDER MESSAGES SCREEN =====
async function renderAdminMessages(){
  var wrap = document.getElementById('messages-list');
  if(!wrap) return;
  wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1n\u00ed...</div>';

  try {
    var msgs = await apiFetchAdminMessages();
    if(!msgs || msgs.length === 0){
      wrap.innerHTML = '<div style="text-align:center;padding:40px 20px;">' +
        '<div style="font-size:48px;margin-bottom:12px;">\ud83d\udce8</div>' +
        '<div style="font-size:14px;font-weight:700;color:var(--black);margin-bottom:4px;">\u017d\u00e1dn\u00e9 zpr\u00e1vy</div>' +
        '<div style="font-size:12px;color:var(--g400);line-height:1.5;">Zat\u00edm nem\u00e1te \u017e\u00e1dn\u00e9 zpr\u00e1vy z Moto Go centr\u00e1ly. Zpr\u00e1vy se zobraz\u00ed jako reakce na va\u0161e SOS hl\u00e1\u0161en\u00ed.</div>' +
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
  } catch(e){
    console.error('renderAdminMessages error:', e);
    wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--red);">Chyba p\u0159i na\u010d\u00edt\u00e1n\u00ed zpr\u00e1v</div>';
  }
}

function _msgIcon(type){
  var icons = {
    sos_response: '\ud83d\ude91',
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
