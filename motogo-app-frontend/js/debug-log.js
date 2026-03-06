// ===== DEBUG-LOG.JS – On-screen diagnostic logger (v4.1.0) =====
// Zachytává console.log/warn/error a zobrazuje na obrazovce.
// Otevřít: 3x tap na logo MotoGo24 nebo zavolat MgDebug.show()

var MgDebug = (function(){
  'use strict';
  var _logs = [];
  var _maxLogs = 80;
  var _panelId = 'mg-debug-panel';
  var _visible = false;
  var _origLog = console.log;
  var _origWarn = console.warn;
  var _origErr = console.error;

  function _ts(){
    var d = new Date();
    return ('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2)+':'+('0'+d.getSeconds()).slice(-2);
  }

  function _add(level, args){
    var msg = Array.prototype.slice.call(args).map(function(a){
      if(a === null) return 'null';
      if(a === undefined) return 'undefined';
      if(typeof a === 'object'){
        try { return JSON.stringify(a).substring(0, 200); } catch(e){ return String(a); }
      }
      return String(a);
    }).join(' ');
    _logs.push({t: _ts(), l: level, m: msg});
    if(_logs.length > _maxLogs) _logs.shift();
    if(_visible) _render();
  }

  // Přepsat console metody
  console.log = function(){
    _origLog.apply(console, arguments);
    _add('LOG', arguments);
  };
  console.warn = function(){
    _origWarn.apply(console, arguments);
    _add('WRN', arguments);
  };
  console.error = function(){
    _origErr.apply(console, arguments);
    _add('ERR', arguments);
  };

  // Zachytit JS chyby
  window.addEventListener('error', function(e){
    _add('ERR', ['JS: ' + (e.message||'?') + ' @ ' + (e.filename||'?') + ':' + (e.lineno||'?')]);
  });

  // Zachytit unhandled promise rejection
  window.addEventListener('unhandledrejection', function(e){
    _add('ERR', ['Promise: ' + (e.reason ? (e.reason.message || String(e.reason)) : '?')]);
  });

  function _getPanel(){
    var el = document.getElementById(_panelId);
    if(!el){
      el = document.createElement('div');
      el.id = _panelId;
      el.style.cssText = 'display:none;position:fixed;top:0;left:0;right:0;bottom:0;z-index:999999;' +
        'background:rgba(0,0,0,0.95);color:#0f0;font-family:monospace;font-size:10px;' +
        'overflow-y:auto;padding:8px;padding-top:40px;-webkit-overflow-scrolling:touch;';
      // Header bar
      var hdr = document.createElement('div');
      hdr.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:1000000;background:#111;' +
        'padding:6px 10px;display:flex;justify-content:space-between;align-items:center;';
      hdr.innerHTML = '<span style="color:#74FB71;font-weight:bold;font-size:12px;">MotoGo24 Debug v4.1.0</span>' +
        '<span>' +
        '<button onclick="MgDebug.copyAll()" style="background:#333;color:#fff;border:none;padding:4px 8px;margin-right:4px;border-radius:4px;font-size:10px;">Copy</button>' +
        '<button onclick="MgDebug.clear()" style="background:#333;color:#fff;border:none;padding:4px 8px;margin-right:4px;border-radius:4px;font-size:10px;">Clear</button>' +
        '<button onclick="MgDebug.hide()" style="background:#c00;color:#fff;border:none;padding:4px 8px;border-radius:4px;font-size:10px;">X</button>' +
        '</span>';
      el.appendChild(hdr);
      var content = document.createElement('div');
      content.id = _panelId + '-content';
      el.appendChild(content);
      document.body.appendChild(el);
    }
    return el;
  }

  function _render(){
    var el = document.getElementById(_panelId + '-content');
    if(!el) return;
    var colors = {LOG:'#0f0', WRN:'#ff0', ERR:'#f44'};
    var html = '';
    // Status info at top
    html += '<div style="color:#888;margin-bottom:6px;border-bottom:1px solid #333;padding-bottom:4px;">';
    html += 'supabase: ' + (window.supabase ? '<span style="color:#0f0">OK</span>' : '<span style="color:#f44">NULL</span>');
    html += ' | online: ' + (navigator.onLine ? '<span style="color:#0f0">YES</span>' : '<span style="color:#f44">NO</span>');
    html += ' | config: ' + (window.MOTOGO_CONFIG ? '<span style="color:#0f0">OK</span>' : '<span style="color:#f44">MISSING</span>');
    html += ' | session: ' + (localStorage.getItem('mg_current_session') ? '<span style="color:#0f0">YES</span>' : '<span style="color:#888">NO</span>');
    html += '</div>';
    for(var i = 0; i < _logs.length; i++){
      var l = _logs[i];
      var c = colors[l.l] || '#0f0';
      html += '<div style="color:'+c+';margin-bottom:2px;word-break:break-all;">' +
        '<span style="color:#666;">' + l.t + '</span> ' +
        '<span style="color:'+c+';font-weight:bold;">[' + l.l + ']</span> ' +
        l.m.replace(/</g,'&lt;') + '</div>';
    }
    el.innerHTML = html;
    el.scrollTop = el.scrollHeight;
  }

  function show(){
    var p = _getPanel();
    p.style.display = 'block';
    _visible = true;
    _render();
  }

  function hide(){
    var p = document.getElementById(_panelId);
    if(p) p.style.display = 'none';
    _visible = false;
  }

  function clear(){
    _logs = [];
    _render();
  }

  function copyAll(){
    var text = _logs.map(function(l){ return l.t+' ['+l.l+'] '+l.m; }).join('\n');
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(text).then(function(){
        _origLog.call(console, '[MgDebug] Zkopírováno do schránky');
      });
    } else {
      // Fallback
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0;';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }
  }

  // Triple-tap aktivace: 3x tap kamkoliv za 1.5s
  var _tapCount = 0;
  var _tapTimer = null;
  document.addEventListener('click', function(e){
    // Ignoruj kliknutí uvnitř debug panelu
    if(e.target.closest && e.target.closest('#'+_panelId)) return;
    _tapCount++;
    if(_tapCount === 1){
      _tapTimer = setTimeout(function(){ _tapCount = 0; }, 1500);
    }
    if(_tapCount >= 5){
      clearTimeout(_tapTimer);
      _tapCount = 0;
      if(_visible) hide(); else show();
    }
  });

  // Log startup info
  console.log('[MG] Debug logger aktivní (5x tap = debug panel)');
  console.log('[MG] navigator.onLine:', navigator.onLine);
  console.log('[MG] MOTOGO_CONFIG:', window.MOTOGO_CONFIG ? 'OK' : 'CHYBÍ');
  console.log('[MG] window.supabase (SDK):', typeof window.supabase, window.supabase ? 'loaded' : 'null');
  console.log('[MG] User-Agent:', navigator.userAgent);

  return {
    show: show,
    hide: hide,
    clear: clear,
    copyAll: copyAll,
    logs: function(){ return _logs; }
  };
})();
