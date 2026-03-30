// ===== OFFLINE-GUARD.JS – Blokuje akce když není připojení =====
// Zobrazí uživateli jasnou hlášku místo tichého selhání.

var OfflineGuard = (function(){
    'use strict';

    var _overlayId = 'motogo-offline-overlay';
    var _checkInterval = null;

    /** Quick online check (sync). */
    function _isOnline() {
        if (!navigator.onLine) return false;
        if (typeof window.supabase === 'undefined' || !window.supabase) return false;
        return true;
    }

    /** Real async ping to Supabase REST endpoint. */
    function _pingSupabase(cb) {
        var cfg = window.MOTOGO_CONFIG || {};
        if (!cfg.SUPABASE_URL) { cb(false); return; }
        fetch(cfg.SUPABASE_URL + '/rest/v1/', {method: 'HEAD', headers: {'apikey': cfg.SUPABASE_ANON_KEY || ''}})
            .then(function(){ cb(true); })
            .catch(function(){ cb(false); });
    }

    /** Zobrazí offline overlay. */
    function _showOverlay() {
        if (document.getElementById(_overlayId)) return;
        var div = document.createElement('div');
        div.id = _overlayId;
        div.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;z-index:99999;' +
            'background:rgba(15,26,20,0.95);display:flex;flex-direction:column;' +
            'align-items:center;justify-content:center;padding:32px;text-align:center;';
        div.innerHTML = '<div style="font-size:48px;margin-bottom:16px;">📡</div>' +
            '<div style="color:#fff;font-size:18px;font-weight:800;margin-bottom:8px;">' +
            (typeof _t==='function'?(_t('offline').title||'No internet connection'):'No internet connection')+'</div>' +
            '<div style="color:#8aab99;font-size:14px;margin-bottom:24px;">' +
            (typeof _t==='function'?(_t('offline').sub||'Internet connection is required to use MotoGo24.'):'Internet connection is required to use MotoGo24.')+'<br>'+(typeof _t==='function'?(_t('offline').hint||'Check your Wi-Fi or mobile data.'):'Check your Wi-Fi or mobile data.')+'</div>' +
            '<button onclick="OfflineGuard.retry()" style="background:#74FB71;color:#0f1a14;' +
            'border:none;border-radius:50px;padding:14px 32px;font-size:14px;font-weight:800;' +
            'cursor:pointer;text-transform:uppercase;letter-spacing:0.5px;">'+(typeof _t==='function'?(_t('offline').retryBtn||'Retry'):'Retry')+'</button>';
        document.body.appendChild(div);
    }

    /** Skryje offline overlay. */
    function _hideOverlay() {
        var el = document.getElementById(_overlayId);
        if (el) el.remove();
    }

    /** Pokus o opětovné připojení. */
    function retry() {
        if (_isOnline()) {
            _hideOverlay();
            return;
        }
        // Zkus reálný ping na Supabase
        var cfg = window.MOTOGO_CONFIG || {};
        if (cfg.SUPABASE_URL) {
            fetch(cfg.SUPABASE_URL + '/rest/v1/', {
                method: 'HEAD',
                headers: { 'apikey': cfg.SUPABASE_ANON_KEY || '' }
            }).then(function() {
                _hideOverlay();
                window.location.reload();
            }).catch(function() {
                // Stále offline — overlay zůstane
                var btn = document.querySelector('#' + _overlayId + ' button');
                if (btn) {
                    btn.textContent = (typeof _t==='function'?(_t('offline').stillOffline||'Still offline\u2026'):'Still offline\u2026');
                    setTimeout(function(){ btn.textContent = (typeof _t==='function'?(_t('offline').retryBtn||'Retry'):'Retry'); }, 2000);
                }
            });
        }
    }

    /** Zkontroluje stav a zobrazí/skryje overlay. Volat při startu appky. */
    function check() {
        if (!_isOnline()) {
            _showOverlay();
        } else {
            _hideOverlay();
        }
    }

    /** Spustí periodickou kontrolu (každých 5s). */
    function startWatching() {
        check();
        window.addEventListener('online', function(){ _hideOverlay(); });
        window.addEventListener('offline', function(){ _showOverlay(); });
        _checkInterval = setInterval(check, 5000);
    }

    /** Guard pro akce — volat před každou důležitou operací (registrace, login, booking). */
    function requireOnline(callback) {
        if (_isOnline()) {
            callback();
        } else {
            _showOverlay();
        }
    }

    return {
        check: check,
        retry: retry,
        startWatching: startWatching,
        requireOnline: requireOnline,
        isOnline: _isOnline,
        pingSupabase: _pingSupabase
    };
})();
