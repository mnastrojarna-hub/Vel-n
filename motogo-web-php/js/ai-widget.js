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

  // i18n strings
  var T = {
    cs: { open: 'Zeptejte se AI', placeholder: 'Napište dotaz...', send: 'Odeslat',
          welcome: 'Ahoj! Jsem AI asistent MotoGo24. Pomůžu ti najít motorku, spočítat cenu, nebo odpovědět na otázky o pronájmu. Co potřebuješ?',
          thinking: 'Přemýšlím...', error: 'Něco se nepovedlo. Zavolejte +420 774 256 271.', close: 'Zavřít chat', clear: 'Začít znovu',
          tos: 'Konverzace s AI je informativní; přesné podmínky najdeš ve smlouvě.' },
    en: { open: 'Ask AI', placeholder: 'Ask anything...', send: 'Send',
          welcome: 'Hi! I\'m the MotoGo24 AI assistant. I can help you find a motorcycle, calculate prices, or answer rental questions. What do you need?',
          thinking: 'Thinking...', error: 'Something went wrong. Call +420 774 256 271.', close: 'Close chat', clear: 'Start over',
          tos: 'AI conversations are informational; binding terms are in the contract.' },
    de: { open: 'KI fragen', placeholder: 'Frage stellen...', send: 'Senden',
          welcome: 'Hallo! Ich bin der MotoGo24 KI-Assistent. Ich helfe dir, ein Motorrad zu finden, Preise zu berechnen oder Mietfragen zu beantworten.',
          thinking: 'Denke nach...', error: 'Etwas ist schiefgelaufen. Rufen Sie +420 774 256 271 an.', close: 'Chat schließen', clear: 'Neu starten',
          tos: 'KI-Gespräche sind informativ; verbindlich ist der Vertrag.' },
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

    function open() {
      panel.classList.add('open');
      bubble.setAttribute('aria-expanded', 'true');
      bubble.textContent = '✕';
      bubble.setAttribute('aria-label', t.close);
      if (!welcomed) {
        welcomed = true;
        appendMsg('assistant', t.welcome);
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
          // Pokud agent volal redirect_to_booking → CTA tlačítko
          if (data.tool_uses && data.tool_uses.length) {
            for (var i = 0; i < data.tool_uses.length; i++) {
              var tu = data.tool_uses[i];
              if (tu.name === 'redirect_to_booking' && tu.result && tu.result.url) {
                var cta = el('a', {
                  href: tu.result.url, target: '_blank', rel: 'noopener',
                  class: 'btn btngreen', style: 'display:inline-block;margin-top:8px;background:#74FB71;color:#0b0b0b;padding:8px 16px;border-radius:18px;text-decoration:none;font-weight:700;font-size:13px',
                }, ['Pokračovat k rezervaci →']);
                msgs.lastChild.appendChild(cta);
              }
            }
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
