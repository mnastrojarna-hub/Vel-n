// ============================================================
// MotoGo24 Doc Scanner — app.js (config, debug log, init)
// ============================================================

var AppConfig = {
  EDGE_URL: 'https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/receive-invoice',
  // Bezpečnostní fix 2026-06-10: API klíč už NENÍ natvrdo v bundlu (kdokoli s APK
  // ho mohl vytáhnout). Účetní ho zadá jednou v aplikaci, uloží se do localStorage.
  // Po rotaci secretu INVOICE_API_KEY ve Supabase je nutné zadat nový klíč.
  get API_KEY() { return localStorage.getItem('mg_invoice_api_key') || ''; },
  set API_KEY(v) { localStorage.setItem('mg_invoice_api_key', v || ''); },
  MAX_SIZE_MB: 4
};

// Při startu si vyžádá API klíč, pokud ještě není uložený.
function ensureApiKey() {
  if (!AppConfig.API_KEY) {
    var k = window.prompt('Zadejte přístupový klíč doc-scanneru (INVOICE_API_KEY):');
    if (k) AppConfig.API_KEY = k.trim();
  }
  return !!AppConfig.API_KEY;
}

// Current state
var AppState = {
  currentPhoto: null   // base64 string
};

// ── Debug Logger ──────────────────────────────────────

var DebugLog = {
  entries: [],
  maxEntries: 200,
  visible: false,

  log: function(level, tag, msg, data) {
    var ts = new Date().toISOString().substr(11, 12);
    var entry = { ts: ts, level: level, tag: tag, msg: msg, data: data };
    this.entries.push(entry);
    if (this.entries.length > this.maxEntries) {
      this.entries.shift();
    }
    // Console output
    var prefix = '[' + ts + '] [' + level + '] [' + tag + '] ';
    if (level === 'ERROR') {
      console.error(prefix + msg, data || '');
    } else if (level === 'WARN') {
      console.warn(prefix + msg, data || '');
    } else {
      console.log(prefix + msg, data || '');
    }
    this._render();
  },

  info: function(tag, msg, data) { this.log('INFO', tag, msg, data); },
  warn: function(tag, msg, data) { this.log('WARN', tag, msg, data); },
  error: function(tag, msg, data) { this.log('ERROR', tag, msg, data); },

  toggle: function() {
    this.visible = !this.visible;
    var panel = document.getElementById('debug-panel');
    if (panel) panel.hidden = !this.visible;
  },

  clear: function() {
    this.entries = [];
    this._render();
  },

  _render: function() {
    var el = document.getElementById('debug-log');
    if (!el) return;
    // Bezpečnostní fix 2026-06-10: escapuj tag/msg/data (mohou obsahovat
    // serverová OCR data) před vložením do innerHTML.
    var esc = function(s) {
      return String(s == null ? '' : s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    };
    var html = this.entries.map(function(e) {
      var cls = 'debug-' + esc(e.level.toLowerCase());
      var line = '<span class="' + cls + '">[' + esc(e.ts) + '] '
        + esc(e.level) + ' [' + esc(e.tag) + '] ' + esc(e.msg);
      if (e.data !== undefined && e.data !== null) {
        try {
          var d = typeof e.data === 'string' ? e.data : JSON.stringify(e.data).substring(0, 300);
          line += ' | ' + esc(d);
        } catch (_) {}
      }
      line += '</span>';
      return line;
    }).join('\n');
    el.innerHTML = '<pre>' + html + '</pre>';
    el.scrollTop = el.scrollHeight;
  }
};

// ── Initialization ───────────────────────────────────

document.addEventListener('DOMContentLoaded', function() {
  DebugLog.info('INIT', 'App starting...');
  DebugLog.info('INIT', 'Platform: ' + navigator.userAgent.substring(0, 80));
  DebugLog.info('INIT', 'Edge URL: ' + AppConfig.EDGE_URL);
  DocUI.renderHistory();
  DebugLog.info('INIT', 'App ready');
});
