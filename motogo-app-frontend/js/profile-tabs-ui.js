// ===== PROFILE-TABS-UI.JS – Tabbed hub for messages, invoices, contracts =====
// Filter & sort by date and type

var _phubTab = 'messages';
var _phubData = { messages: [], invoices: [], contracts: [] };

function phubOpenTab(tab) {
  _phubTab = tab || 'messages';
  goTo('s-profile-hub');
}

// ===== TAB SWITCHING =====
function phubSwitchTab(tab) {
  _phubTab = tab;
  ['messages','invoices','contracts'].forEach(function(t) {
    var btn = document.getElementById('phub-tab-' + t);
    if (!btn) return;
    if (t === tab) {
      btn.classList.add('phub-tab-active');
      btn.style.background = 'var(--green)';
      btn.style.color = '#fff';
      btn.style.borderColor = 'var(--green)';
    } else {
      btn.classList.remove('phub-tab-active');
      btn.style.background = '#fff';
      btn.style.color = 'var(--black)';
      btn.style.borderColor = 'var(--g200)';
    }
  });
  _phubUpdateTypeFilter();
  phubApplyFilters();
}

// ===== MAIN RENDER =====
async function renderProfileHub() {
  var wrap = document.getElementById('phub-content');
  if (!wrap) return;
  wrap.innerHTML = '<div style="text-align:center;padding:20px;color:var(--g400);">\u23f3 Na\u010d\u00edt\u00e1m...</div>';

  // Load all data in parallel
  try {
    var msgP = _phubLoadMessages();
    var docP = apiFetchDocuments();
    var results = await Promise.all([msgP, docP]);
    _phubData.messages = results[0] || [];
    var allDocs = results[1] || [];
    _phubData.invoices = allDocs.filter(function(d) {
      return d.type === 'invoice_advance' || d.type === 'invoice_final' ||
        d.type === 'invoice_shop' || d.type === 'payment_receipt';
    });
    _phubData.contracts = allDocs.filter(function(d) {
      return d.type === 'contract' || d.type === 'protocol' || d.type === 'vop';
    });
  } catch (e) { console.error('renderProfileHub:', e); }

  // Set active tab visuals
  phubSwitchTab(_phubTab);
}

async function _phubLoadMessages() {
  var items = [];
  // Admin messages (notifications)
  if (typeof apiFetchAdminMessages === 'function') {
    var msgs = await apiFetchAdminMessages();
    if (msgs) msgs.forEach(function(m) {
      items.push({
        id: m.id, _type: 'notif', _src: m,
        title: m.title || 'Zpráva z Moto Go',
        text: m.message || '',
        date: m.created_at || '',
        type: m.type || 'info',
        unread: !m.read
      });
    });
  }
  // Chat threads
  if (typeof apiFetchMyThreads === 'function') {
    var threads = await apiFetchMyThreads();
    if (threads) threads.forEach(function(t) {
      var msgs2 = t.messages || [];
      var last = msgs2.length > 0 ? msgs2[msgs2.length - 1] : null;
      var unread = msgs2.filter(function(m) { return m.direction === 'admin' && !m.read_at; }).length;
      items.push({
        id: t.id, _type: 'thread', _src: t,
        title: t.subject || 'Konverzace',
        text: last ? (last.content || '').slice(0, 80) : '',
        date: t.last_message_at || t.created_at || '',
        type: t.subject && t.subject.indexOf('SOS:') === 0 ? 'sos' : 'chat',
        unread: unread > 0
      });
    });
  }
  return items;
}

// ===== TYPE FILTER OPTIONS =====
function _phubUpdateTypeFilter() {
  var sel = document.getElementById('phub-type-filter');
  if (!sel) return;
  var opts = '<option value="">V\u0161echny typy</option>';
  if (_phubTab === 'messages') {
    opts += '<option value="notif">Ozn\u00e1men\u00ed</option>';
    opts += '<option value="thread">Konverzace</option>';
    opts += '<option value="sos">SOS</option>';
  } else if (_phubTab === 'invoices') {
    opts += '<option value="invoice_advance">Z\u00e1lohov\u00e1 faktura</option>';
    opts += '<option value="payment_receipt">Doklad k platb\u011b</option>';
    opts += '<option value="invoice_final">Faktura</option>';
    opts += '<option value="invoice_shop">Shop faktura</option>';
  } else {
    opts += '<option value="contract">Smlouva</option>';
    opts += '<option value="protocol">P\u0159ed\u00e1vac\u00ed protokol</option>';
    opts += '<option value="vop">VOP</option>';
  }
  sel.innerHTML = opts;
}

// ===== FILTER + SORT + RENDER =====
function phubApplyFilters() {
  var wrap = document.getElementById('phub-content');
  if (!wrap) return;
  var sortVal = (document.getElementById('phub-sort') || {}).value || 'date_desc';
  var typeVal = (document.getElementById('phub-type-filter') || {}).value || '';
  var data = (_phubData[_phubTab] || []).slice();

  // Filter by type
  if (typeVal) {
    if (_phubTab === 'messages') {
      if (typeVal === 'sos') {
        data = data.filter(function(d) { return d.type === 'sos'; });
      } else {
        data = data.filter(function(d) { return d._type === typeVal; });
      }
    } else {
      data = data.filter(function(d) { return d.type === typeVal; });
    }
  }

  // Sort
  var asc = sortVal === 'date_asc';
  data.sort(function(a, b) {
    var da = new Date(a.date || a.created_at || 0);
    var db = new Date(b.date || b.created_at || 0);
    return asc ? da - db : db - da;
  });

  // Render
  if (data.length === 0) {
    var emptyIcon = _phubTab === 'messages' ? '\ud83d\udce8' : _phubTab === 'invoices' ? '\ud83e\uddfe' : '\ud83d\udcc4';
    var emptyText = _phubTab === 'messages' ? '\u017d\u00e1dn\u00e9 zpr\u00e1vy' : _phubTab === 'invoices' ? '\u017d\u00e1dn\u00e9 faktury' : '\u017d\u00e1dn\u00e9 dokumenty';
    wrap.innerHTML = '<div style="text-align:center;padding:30px 20px;">' +
      '<div style="font-size:40px;margin-bottom:10px;">' + emptyIcon + '</div>' +
      '<div style="font-size:13px;font-weight:700;color:var(--black);">' + emptyText + '</div>' +
      '<div style="font-size:11px;color:var(--g400);margin-top:4px;">Zat\u00edm tu nic nen\u00ed.</div></div>';
    return;
  }

  var html = '';
  if (_phubTab === 'messages') html = _phubRenderMessages(data);
  else if (_phubTab === 'invoices') html = _phubRenderInvoices(data);
  else html = _phubRenderContracts(data);
  wrap.innerHTML = html;
}

// ===== RENDER: MESSAGES =====
function _phubRenderMessages(data) {
  var html = '';
  data.forEach(function(m) {
    var dt = m.date ? new Date(m.date) : new Date();
    var fmt = dt.toLocaleDateString('cs-CZ') + ' ' + dt.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' });
    var isThread = m._type === 'thread';
    var icon = isThread ? (m.type === 'sos' ? '\ud83d\ude91' : '\ud83d\udcac') : _phubMsgIcon(m.type);
    var badge = m.unread ? '<div class="phub-unread-dot"></div>' : '';
    var typeLabel = isThread ? 'Konverzace' : 'Ozn\u00e1men\u00ed';
    var onclick = isThread ? 'openThread(\'' + m.id + '\')' : 'markMsgRead(\'' + m.id + '\',this)';

    html += '<div class="phub-item' + (m.unread ? ' phub-item-unread' : '') + '" onclick="' + onclick + '">' +
      '<div class="phub-item-icon">' + icon + badge + '</div>' +
      '<div class="phub-item-body">' +
      '<div class="phub-item-title">' + _phubEsc(m.title) + '</div>' +
      '<div class="phub-item-text">' + _phubEsc(m.text) + '</div>' +
      '<div class="phub-item-meta">' +
      '<span class="phub-type-badge">' + typeLabel + '</span>' +
      '<span>' + fmt + '</span></div>' +
      '</div></div>';
  });
  return html;
}

// ===== RENDER: INVOICES =====
function _phubRenderInvoices(data) {
  var html = '';
  data.forEach(function(d) {
    var dt = new Date(d.date || d.created_at);
    var fmt = dt.toLocaleDateString('cs-CZ');
    var isShop = d.type === 'invoice_shop';
    var isReceipt = d.type === 'payment_receipt';
    var icon = isShop ? '\ud83d\uded2' : isReceipt ? '\u2705' : (d.type === 'invoice_advance' ? '\ud83e\uddfe' : '\ud83d\udcb0');
    var label = isShop ? 'Shop faktura' : isReceipt ? 'Doklad k platb\u011b' : (d.type === 'invoice_advance' ? 'Z\u00e1lohov\u00e1 faktura' : 'Faktura');
    var amt = d.amount ? d.amount.toLocaleString('cs-CZ') + ' K\u010d' : '';
    var invType = isReceipt ? 'payment_receipt' : (d.type === 'invoice_advance' ? 'advance' : 'final');
    var inv = d._invoice || null;
    var invId = (inv && inv.id) ? inv.id : d.id;
    var onclick = isShop ? 'showShopOrderDetail(\'' + d.id + '\')' : 'showInvoice(\'' + d.booking_id + '\',\'' + invType + '\',\'' + (invId || '') + '\')';
    var itemName = isShop ? (d.shop_items || 'Shop') : (d.moto_name || '');

    html += '<div class="phub-item" onclick="' + onclick + '">' +
      '<div class="phub-item-icon">' + icon + '</div>' +
      '<div class="phub-item-body">' +
      '<div class="phub-item-title">' + _phubEsc(itemName) + '</div>' +
      '<div class="phub-item-text">' + label + (d.res_num ? ' \u00b7 ' + d.res_num : '') + '</div>' +
      '<div class="phub-item-meta">' +
      '<span class="phub-type-badge">' + label + '</span>' +
      '<span>' + fmt + '</span></div>' +
      '</div>' +
      (amt ? '<div class="phub-item-amt">' + amt + '</div>' : '') +
      '</div>';
  });
  return html;
}

// ===== RENDER: CONTRACTS =====
function _phubRenderContracts(data) {
  var html = '';
  data.forEach(function(d) {
    var dt = new Date(d.date || d.created_at);
    var fmt = dt.toLocaleDateString('cs-CZ');
    var icon = d.type === 'vop' ? '\ud83d\udcdc' : d.type === 'protocol' ? '\ud83d\udccb' : '\ud83d\udcc4';
    var label = d.type === 'vop' ? 'VOP' : d.type === 'protocol' ? 'P\u0159ed\u00e1vac\u00ed protokol' : 'Smlouva';
    var onclick = d.type === 'vop' ? 'showVOP()' :
      d.type === 'protocol' ? 'showDigitalProtocol(\'' + d.booking_id + '\')' :
      'showRentalContract(\'' + d.booking_id + '\')';

    html += '<div class="phub-item" onclick="' + onclick + '">' +
      '<div class="phub-item-icon">' + icon + '</div>' +
      '<div class="phub-item-body">' +
      '<div class="phub-item-title">' + label + (d.moto_name ? ' \u2013 ' + _phubEsc(d.moto_name) : '') + '</div>' +
      '<div class="phub-item-text">' + (d.res_num || '') + '</div>' +
      '<div class="phub-item-meta">' +
      '<span class="phub-type-badge">' + label + '</span>' +
      '<span>' + fmt + '</span></div>' +
      '</div></div>';
  });
  // Always show VOP link if no vop in data
  var hasVop = data.some(function(d) { return d.type === 'vop'; });
  if (!hasVop) {
    html = '<div class="phub-item" onclick="showVOP()">' +
      '<div class="phub-item-icon">\ud83d\udcdc</div>' +
      '<div class="phub-item-body">' +
      '<div class="phub-item-title">V\u0161eobecn\u00e9 obchodn\u00ed podm\u00ednky</div>' +
      '<div class="phub-item-text">Bc. Petra Semor\u00e1dov\u00e1</div>' +
      '<div class="phub-item-meta"><span class="phub-type-badge">VOP</span></div>' +
      '</div></div>' + html;
  }
  return html;
}

// ===== HELPERS =====
function _phubMsgIcon(type) {
  var icons = {
    sos_response: '\ud83d\ude91', sos_auto: '\ud83d\ude91',
    accident_response: '\u26a0\ufe0f', replacement: '\ud83d\udee0\ufe0f',
    tow: '\ud83d\ude9a', info: '\u2139\ufe0f', thanks: '\ud83d\ude4f',
    voucher: '\ud83c\udf81'
  };
  return icons[type] || '\ud83d\udce9';
}

function _phubEsc(s) {
  if (!s) return '';
  var d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}
