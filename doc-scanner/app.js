// ============================================================
// MotoGo24 Doc Scanner — app.js (config, debug log, init)
// ============================================================

var AppConfig = {
  EDGE_URL: 'https://vnwnqteskbykeucanlhk.supabase.co/functions/v1/receive-invoice',
  API_KEY: 'a745cb2badbe46899e16447c092299fe9447ef520523a0f5b379605c8e884829',
  MAX_SIZE_MB: 4
};

// Current state
var AppState = {
  currentPhoto: null,   // base64 string
  isNative: false,      // true if running inside Capacitor native
  hasCamera: false       // camera permission granted
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
    var html = this.entries.map(function(e) {
      var cls = 'debug-' + e.level.toLowerCase();
      var line = '<span class="' + cls + '">[' + e.ts + '] '
        + e.level + ' [' + e.tag + '] ' + e.msg;
      if (e.data !== undefined && e.data !== null) {
        try {
          var d = typeof e.data === 'string' ? e.data : JSON.stringify(e.data).substring(0, 300);
          line += ' | ' + d;
        } catch (_) {}
      }
      line += '</span>';
      return line;
    }).join('\n');
    el.innerHTML = '<pre>' + html + '</pre>';
    el.scrollTop = el.scrollHeight;
  }
};

// ── Platform detection ───────────────────────────────

function detectPlatform() {
  if (typeof Capacitor !== 'undefined' && Capacitor.isNativePlatform &&
      Capacitor.isNativePlatform()) {
    AppState.isNative = true;
    DebugLog.info('INIT', 'Platform: Capacitor Native (' + Capacitor.getPlatform() + ')');
  } else if (typeof Capacitor !== 'undefined') {
    AppState.isNative = false;
    DebugLog.info('INIT', 'Platform: Capacitor Web (browser fallback)');
  } else {
    AppState.isNative = false;
    DebugLog.info('INIT', 'Platform: Pure Web (no Capacitor)');
  }
}

// ── Initialization ───────────────────────────────────

document.addEventListener('DOMContentLoaded', function() {
  DebugLog.info('INIT', 'App starting...');
  detectPlatform();

  // Request permissions early on native
  if (AppState.isNative) {
    DocCamera.requestPermissions();
  } else {
    DebugLog.info('INIT', 'Web mode - using file input fallback');
    AppState.hasCamera = true;
  }

  DocUI.renderHistory();
  DebugLog.info('INIT', 'App ready');
});
