/**
 * MotoGo24 — AI Booking Widget
 *
 * Floating chat bubble. Klika otevře panel s AI asistentem napojeným
 * na ai-public-agent edge funkci. Anti-halucinace: agent volá tools
 * pro reálná data (motorky, ceny, dostupnost) a nikdy nevymýšlí.
 *
 * Inicializace: <script src="/js/ai-widget.js" defer></script>
 * Konfigurace přes window.MOTOGO_AI_CONFIG = { url, lang, ... }
 */

(function() {
  'use strict';

  if (window.__motogoAiWidget) return;
  window.__motogoAiWidget = true;

  // Config
  var SUPABASE_URL = (window.MOTOGO_CONFIG && window.MOTOGO_CONFIG.SUPABASE_URL)
    || 'https://vnwnqteskbykeucanlhk.supabase.co';
  var SUPABASE_ANON_KEY = (window.MOTOGO_CONFIG && window.MOTOGO_CONFIG.SUPABASE_ANON_KEY) || '';
  var LANG = document.documentElement.lang ? document.documentElement.lang.slice(0, 2) : 'cs';
  var API = SUPABASE_URL + '/functions/v1/ai-public-agent';

  // i18n strings (welcome se případně přepíše hláškou z app_settings)
  var T = {
    cs: { open: 'Zeptejte se AI', placeholder: 'Napište dotaz nebo začněte rezervaci...', send: 'Odeslat',
          welcome: 'Dobrý den, jsem rezervační asistent MotoGo24. Co potřebujete — najít motorku, spočítat cenu, nebo rovnou rezervovat?',
          thinking: 'Přemýšlím...', error: 'Něco se nepovedlo. Zavolejte +420 774 256 271.', close: 'Zavřít chat', clear: 'Začít znovu',
          tos: 'Konverzace s AI je informativní; přesné podmínky najdeš ve smlouvě.',
          ctaPay: 'Pokračovat k platbě →', ctaBook: 'Pokračovat k rezervaci →' },
    en: { open: 'Ask AI', placeholder: 'Ask or start a booking...', send: 'Send',
          welcome: 'Hi, I\'m the MotoGo24 booking assistant. What do you need — find a motorcycle, get a price, or book straight away?',
          thinking: 'Thinking...', error: 'Something went wrong. Call +420 774 256 271.', close: 'Close chat', clear: 'Start over',
          tos: 'AI conversations are informational; binding terms are in the contract.',
          ctaPay: 'Continue to payment →', ctaBook: 'Continue to booking →' },
    de: { open: 'KI fragen', placeholder: 'Frage stellen oder buchen...', send: 'Senden',
          welcome: 'Hallo, ich bin der Buchungsassistent von MotoGo24. Was brauchen Sie — ein Motorrad finden, Preis berechnen oder gleich buchen?',
          thinking: 'Denke nach...', error: 'Etwas ist schiefgelaufen. Rufen Sie +420 774 256 271 an.', close: 'Chat schließen', clear: 'Neu starten',
          tos: 'KI-Gespräche sind informativ; verbindlich ist der Vertrag.',
          ctaPay: 'Weiter zur Zahlung →', ctaBook: 'Weiter zur Buchung →' },
  };
  var t = T[LANG] || T.cs;

  // ---- DOM ----
  var styles = '\
  #motogo-ai-bubble{position:fixed;right:20px;bottom:20px;z-index:9999;width:64px;height:64px;border-radius:50%;background:#74FB71;color:#0b0b0b;border:none;cursor:pointer;box-shadow:0 4px 16px rgba(0,0,0,.25);font-size:28px;display:flex;align-items:center;justify-content:center;transition:transform .15s ease;font-family:inherit}\
  #motogo-ai-bubble:hover{transform:scale(1.06)}\
  #motogo-ai-bubble[aria-expanded=true]{background:#1a2e22;color:#74FB71}\
  #motogo-ai-panel{position:fixed;right:20px;bottom:96px;z-index:9998;width:380px;max-width:calc(100vw - 40px);height:560px;max-height:calc(100vh - 120px);background:#fff;border-radius:18px;box-shadow:0 12px 40px rgba(0,0,0,.3);display:none;flex-direction:column;overflow:hidden;font-family:Montserrat,system-ui,sans-serif}\
  #motogo-ai-panel.open{display:flex;animation:motogo-pop .2s ease-out}\
  @keyframes motogo-pop{from{opacity:0;transform:translateY(8px) scale(.96)}to{opacity:1;transform:none}}\
  #motogo-ai-header{padding:14px 16px;background:#1a2e22;color:#74FB71;display:flex;align-items:center;justify-content:space-between;font-weight:700}\
  #motogo-ai-header button{background:none;border:none;color:#74FB71;cursor:pointer;font-size:18px;padding:4px 8px}\
  #motogo-ai-messages{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:10px;background:#f8f9fa}\
  .motogo-ai-msg{padding:10px 14px;border-radius:14px;max-width:85%;line-height:1.45;word-wrap:break-word;font-size:14px}\
  .motogo-ai-msg.user{background:#1a2e22;color:#fff;align-self:flex-end;border-bottom-right-radius:4px}\
  .motogo-ai-msg.assistant{background:#fff;color:#0b0b0b;align-self:flex-start;border:1px solid #e3e8e5;border-bottom-left-radius:4px}\
  .motogo-ai-msg.thinking{background:none;border:none;color:#666;font-style:italic;align-self:flex-start;padding:6px 0}\
  .motogo-ai-msg a{color:#1a8c1a;text-decoration:underline}\
  .motogo-ai-tools{font-size:11px;color:#888;margin-top:6px}\
  #motogo-ai-input-row{padding:10px;background:#fff;border-top:1px solid #e3e8e5;display:flex;gap:8px;align-items:flex-end}\
  #motogo-ai-input{flex:1;border:1px solid #d4e8e0;border-radius:18px;padding:10px 14px;font-family:inherit;font-size:14px;resize:none;max-height:100px;min-height:40px}\
  #motogo-ai-input:focus{outline:none;border-color:#74FB71}\
  #motogo-ai-send{background:#74FB71;color:#0b0b0b;border:none;border-radius:18px;padding:10px 16px;cursor:pointer;font-weight:700;font-family:inherit;font-size:13px}\
  #motogo-ai-send:disabled{opacity:.5;cursor:not-allowed}\
  #motogo-ai-tos{font-size:10px;color:#888;text-align:center;padding:6px;background:#fff;border-top:1px solid #e3e8e5}\
  @media (max-width:480px){#motogo-ai-panel{right:10px;bottom:84px;left:10px;width:auto;max-width:none;height:calc(100vh - 100px)}#motogo-ai-bubble{right:14px;bottom:14px}}';

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    if (attrs) for (var k in attrs) {
      if (k === 'class') n.className = attrs[k];
      else if (k.indexOf('on') === 0) n.addEventListener(k.slice(2), attrs[k]);
      else n.setAttribute(k, attrs[k]);
    }
    (children || []).forEach(function(c) {
      if (typeof c === 'string') n.appendChild(document.createTextNode(c));
      else if (c) n.appendChild(c);
    });
    return n;
  }

  function init() {
    var styleEl = el('style');
    styleEl.textContent = styles;
    document.head.appendChild(styleEl);

    var bubble = el('button', {
      id: 'motogo-ai-bubble', type: 'button', 'aria-label': t.open, 'aria-expanded': 'false',
      title: t.open,
    }, ['💬']);

    var msgs = el('div', { id: 'motogo-ai-messages', role: 'log', 'aria-live': 'polite' });
    var input = el('textarea', {
      id: 'motogo-ai-input', placeholder: t.placeholder, rows: '1',
      'aria-label': t.placeholder,
    });
    var sendBtn = el('button', { id: 'motogo-ai-send', type: 'button' }, [t.send]);
    var inputRow = el('div', { id: 'motogo-ai-input-row' }, [input, sendBtn]);
    var tos = el('div', { id: 'motogo-ai-tos' }, [t.tos]);

    var header = el('div', { id: 'motogo-ai-header' }, [
      el('span', null, ['MotoGo24 AI']),
      el('button', { type: 'button', 'aria-label': t.close, title: t.close, onclick: close }, ['✕']),
    ]);

    var panel = el('div', { id: 'motogo-ai-panel', role: 'dialog', 'aria-label': 'MotoGo24 AI' },
      [header, msgs, inputRow, tos]);

    document.body.appendChild(bubble);
    document.body.appendChild(panel);

    // ---- State ----
    var conversation = [];
    var isLoading = false;
    var welcomed = false;
    var customWelcome = null;

    // Načti uvítací zprávu z app_settings (admin si ji může změnit ve Velínu).
    // PostgREST endpoint je veřejný (RLS app_settings = SELECT public).
    (function fetchWelcome() {
      try {
        var url = SUPABASE_URL + '/rest/v1/app_settings?key=eq.ai_public_agent_config&select=value';
        fetch(url, { headers: { 'apikey': SUPABASE_ANON_KEY, 'Authorization': 'Bearer ' + SUPABASE_ANON_KEY } })
          .then(function(r) { return r.ok ? r.json() : []; })
          .then(function(rows) {
            if (rows && rows[0] && rows[0].value) {
              var v = rows[0].value;
              if (v.enabled === false) {
                bubble.style.display = 'none';
                return;
              }
              var key = 'welcome_' + LANG;
              if (v[key] && typeof v[key] === 'string') customWelcome = v[key];
            }
          })
          .catch(function() {});
      } catch (e) {}
    })();

    function open() {
      panel.classList.add('open');
      bubble.setAttribute('aria-expanded', 'true');
      bubble.textContent = '✕';
      bubble.setAttribute('aria-label', t.close);
      if (!welcomed) {
        welcomed = true;
        appendMsg('assistant', customWelcome || t.welcome);
      }
      setTimeout(function() { input.focus(); }, 200);
    }

    function close() {
      panel.classList.remove('open');
      bubble.setAttribute('aria-expanded', 'false');
      bubble.textContent = '💬';
      bubble.setAttribute('aria-label', t.open);
    }

    function toggle() {
      if (panel.classList.contains('open')) close(); else open();
    }

    bubble.addEventListener('click', toggle);

    input.addEventListener('input', function() {
      input.style.height = 'auto';
      input.style.height = Math.min(input.scrollHeight, 100) + 'px';
    });
    input.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        send();
      }
    });
    sendBtn.addEventListener('click', send);

    function appendMsg(role, text, extra) {
      var node = el('div', { class: 'motogo-ai-msg ' + role });
      // Auto-link URL + zachovat newliney
      var safe = text
        .replace(/[<>&]/g, function(c) { return { '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]; })
        .replace(/(https?:\/\/[^\s)]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>')
        .replace(/\n/g, '<br>');
      node.innerHTML = safe;
      if (extra) node.appendChild(extra);
      msgs.appendChild(node);
      msgs.scrollTop = msgs.scrollHeight;
      return node;
    }

    function appendThinking() {
      var n = el('div', { class: 'motogo-ai-msg thinking' }, [t.thinking]);
      msgs.appendChild(n);
      msgs.scrollTop = msgs.scrollHeight;
      return n;
    }

    async function send() {
      if (isLoading) return;
      var text = input.value.trim();
      if (!text) return;
      conversation.push({ role: 'user', content: text });
      appendMsg('user', text);
      input.value = '';
      input.style.height = 'auto';
      isLoading = true;
      sendBtn.disabled = true;
      var thinkingNode = appendThinking();

      try {
        var resp = await fetch(API, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
          },
          body: JSON.stringify({ messages: conversation, lang: LANG }),
        });
        thinkingNode.remove();
        if (!resp.ok) {
          var errText = '';
          try { errText = (await resp.json()).error || ''; } catch(e) {}
          appendMsg('assistant', t.error + (errText ? ' (' + errText + ')' : ''));
        } else {
          var data = await resp.json();
          var reply = data.reply || t.error;
          conversation.push({ role: 'assistant', content: reply });
          appendMsg('assistant', reply);
          // CTA tlačítka — preferujeme platební odkaz z create_booking_request,
          // jinak redirect_to_booking. Hodnota tu.result je už deserializovaná.
          var ctaUrl = data.booking_url || null;
          var ctaLabel = ctaUrl ? t.ctaPay : null;
          if (!ctaUrl && data.tool_uses && data.tool_uses.length) {
            for (var i = 0; i < data.tool_uses.length; i++) {
              var tu = data.tool_uses[i];
              if (tu.name === 'redirect_to_booking' && tu.result && tu.result.url) {
                ctaUrl = tu.result.url;
                ctaLabel = t.ctaBook;
                break;
              }
            }
          }
          if (ctaUrl) {
            var cta = el('a', {
              href: ctaUrl, target: '_blank', rel: 'noopener',
              style: 'display:inline-block;margin-top:8px;background:#74FB71;color:#0b0b0b;padding:8px 16px;border-radius:18px;text-decoration:none;font-weight:700;font-size:13px',
            }, [ctaLabel]);
            msgs.lastChild.appendChild(cta);
          }
        }
      } catch (e) {
        thinkingNode.remove();
        appendMsg('assistant', t.error);
      } finally {
        isLoading = false;
        sendBtn.disabled = false;
        input.focus();
      }
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
