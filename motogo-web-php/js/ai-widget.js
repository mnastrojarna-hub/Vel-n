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
    cs: { open: 'Zeptej se Tomáše', placeholder: 'Napiš co potřebuješ...', send: 'Pošli',
          welcome: 'Čau, tady Tomáš z MotoGo24. Co bys potřeboval — vybrat káru, mrknout na termín, nebo rovnou jedem?',
          thinking: 'Koukám na to...', error: 'Něco se zaseklo, zkus to prosím znovu.', close: 'Zavřít chat', clear: 'Začít znovu',
          tos: 'Konverzace s asistentem je informativní; přesné podmínky najdeš ve smlouvě.',
          ctaPay: 'Pokračovat k platbě →', ctaBook: 'Pokračovat k rezervaci →' },
    en: { open: 'Ask Tom', placeholder: 'Type your question...', send: 'Send',
          welcome: 'Hey, this is Tom from MotoGo24. What do you need — pick a bike, check a date, or shall we book it right away?',
          thinking: 'Looking into it...', error: 'Something hiccuped, please try again.', close: 'Close chat', clear: 'Start over',
          tos: 'AI conversations are informational; binding terms are in the contract.',
          ctaPay: 'Continue to payment →', ctaBook: 'Continue to booking →' },
    de: { open: 'Tom fragen', placeholder: 'Stell deine Frage...', send: 'Senden',
          welcome: 'Servus, hier Tom von MotoGo24. Was brauchst du — ein Bike aussuchen, Termin prüfen oder gleich buchen?',
          thinking: 'Schau gerade...', error: 'Da hakte es kurz, bitte nochmal probieren.', close: 'Chat schließen', clear: 'Neu starten',
          tos: 'KI-Gespräche sind informativ; verbindlich ist der Vertrag.',
          ctaPay: 'Weiter zur Zahlung →', ctaBook: 'Weiter zur Buchung →' },
  };
  var t = T[LANG] || T.cs;

  // ---- DOM ----
  // Responsive sizing strategy:
  //   - dvh (dynamic viewport) is used after vh, so when supported it overrides
  //     and avoids iOS URL-bar / on-screen-keyboard overflow.
  //   - safe-area-inset-bottom respects the iOS home indicator on notched devices.
  //   - Height-based media queries catch landscape phones and short laptop windows
  //     where width-only breakpoints miss; otherwise the panel could exceed the
  //     viewport (the user-reported "popup bigger than screen" bug).
  //   - Input font-size:16px prevents iOS Safari auto-zoom on focus.
  var styles = '\
  #motogo-ai-bubble{position:fixed;right:20px;bottom:20px;bottom:max(20px,env(safe-area-inset-bottom));z-index:9999;width:64px;height:64px;border-radius:50%;background:#74FB71;color:#0b0b0b;border:none;cursor:pointer;box-shadow:0 4px 16px rgba(0,0,0,.25);font-size:28px;display:flex;align-items:center;justify-content:center;transition:transform .15s ease;font-family:inherit}\
  #motogo-ai-bubble:hover{transform:scale(1.06)}\
  #motogo-ai-bubble[aria-expanded=true]{background:#1a2e22;color:#74FB71}\
  #motogo-ai-panel{position:fixed;right:20px;bottom:96px;bottom:calc(96px + env(safe-area-inset-bottom,0px));z-index:9998;width:380px;max-width:calc(100vw - 40px);height:560px;max-height:calc(100vh - 120px);max-height:calc(100dvh - 120px);background:#fff;border-radius:18px;box-shadow:0 12px 40px rgba(0,0,0,.3);display:none;flex-direction:column;overflow:hidden;font-family:Montserrat,system-ui,sans-serif}\
  #motogo-ai-panel.open{display:flex;animation:motogo-pop .2s ease-out}\
  @keyframes motogo-pop{from{opacity:0;transform:translateY(8px) scale(.96)}to{opacity:1;transform:none}}\
  #motogo-ai-header{padding:14px 16px;background:#1a2e22;color:#74FB71;display:flex;align-items:center;justify-content:space-between;font-weight:700;flex-shrink:0}\
  #motogo-ai-header button{background:none;border:none;color:#74FB71;cursor:pointer;font-size:18px;padding:4px 8px}\
  #motogo-ai-messages{flex:1 1 auto;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:16px;display:flex;flex-direction:column;gap:10px;background:#f8f9fa;min-height:0}\
  .motogo-ai-msg{padding:10px 14px;border-radius:14px;max-width:85%;line-height:1.45;word-wrap:break-word;overflow-wrap:break-word;font-size:14px}\
  .motogo-ai-msg.user{background:#1a2e22;color:#fff;align-self:flex-end;border-bottom-right-radius:4px}\
  .motogo-ai-msg.assistant{background:#fff;color:#0b0b0b;align-self:flex-start;border:1px solid #e3e8e5;border-bottom-left-radius:4px}\
  .motogo-ai-msg.thinking{background:none;border:none;color:#666;font-style:italic;align-self:flex-start;padding:6px 0}\
  .motogo-ai-msg a{color:#1a8c1a;text-decoration:underline;word-break:break-word}\
  .motogo-ai-tools{font-size:11px;color:#888;margin-top:6px}\
  #motogo-ai-input-row{padding:10px;background:#fff;border-top:1px solid #e3e8e5;display:flex;gap:8px;align-items:flex-end;flex-shrink:0}\
  #motogo-ai-input{flex:1;min-width:0;border:1px solid #d4e8e0;border-radius:18px;padding:10px 14px;font-family:inherit;font-size:16px;resize:none;max-height:100px;min-height:40px}\
  #motogo-ai-input:focus{outline:none;border-color:#74FB71}\
  #motogo-ai-send{background:#74FB71;color:#0b0b0b;border:none;border-radius:18px;padding:10px 16px;cursor:pointer;font-weight:700;font-family:inherit;font-size:13px;flex-shrink:0;min-height:40px}\
  #motogo-ai-send:disabled{opacity:.5;cursor:not-allowed}\
  #motogo-ai-tos{font-size:10px;color:#888;text-align:center;padding:6px;background:#fff;border-top:1px solid #e3e8e5;flex-shrink:0}\
  body.motogo-ai-open #Up{display:none!important}\
  @media (max-width:600px){#motogo-ai-panel{right:10px;left:10px;width:auto;max-width:none;bottom:84px;bottom:calc(84px + env(safe-area-inset-bottom,0px));height:calc(100vh - 100px);height:calc(100dvh - 100px)}#motogo-ai-bubble{right:14px;bottom:14px;bottom:max(14px,env(safe-area-inset-bottom));width:56px;height:56px;font-size:24px}}\
  @media (max-height:600px){#motogo-ai-panel{height:calc(100vh - 88px);height:calc(100dvh - 88px);bottom:78px}#motogo-ai-bubble{width:52px;height:52px;font-size:22px;bottom:14px}}\
  @media (max-height:420px){#motogo-ai-panel{height:calc(100vh - 70px);height:calc(100dvh - 70px);bottom:62px}#motogo-ai-bubble{width:46px;height:46px;font-size:20px;bottom:10px}}\
  @media (orientation:landscape) and (max-height:500px) and (max-width:900px){#motogo-ai-panel{right:8px;left:auto;width:min(380px,calc(100vw - 16px));max-width:calc(100vw - 16px)}}';

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
      document.body.classList.add('motogo-ai-open');
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
      document.body.classList.remove('motogo-ai-open');
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
      // 1) escape HTML
      var safe = text.replace(/[<>&]/g, function(c) { return { '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]; });
      // 2) markdown links [text](url) — vyrenderujeme PŘED auto-linking, ať se neporouchá Stripe
      //    URL s '#fragment' obsahujícím publishable key. URL musí obsahovat http(s):// a může
      //    obsahovat libovolné non-whitespace znaky kromě uzavírací závorky.
      safe = safe.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
        function(_, label, url) {
          return '<a href="' + url + '" target="_blank" rel="noopener">' + label + '</a>';
        });
      // 3) markdown bold **text**
      safe = safe.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
      // 4) auto-link bare URLs (jen ty, co ještě nejsou v <a>)
      safe = safe.replace(/(^|[^"=>])(https?:\/\/[^\s<)]+)/g,
        function(_, prefix, url) {
          return prefix + '<a href="' + url + '" target="_blank" rel="noopener">' + url + '</a>';
        });
      // 5) newlines
      safe = safe.replace(/\n/g, '<br>');
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

    // ---- Kontext aktuální stránky ----
    // Co tu odesíláme:
    //   - URL + path + dokumentový titulek + první H1 (orientace agenta)
    //   - typ stránky odvozený z URL (home, moto_detail, katalog, shop, shop_detail,
    //     blog, blog_detail, faq, kontakt, jak-pujcit, poukazy, pujcovna, partneri, other)
    //   - klíče parametrů: moto_id, slug, query (pokud lze odvodit)
    //   - aktuálně označený text (až 500 znaků) — když user "čte tohle a chce o tom mluvit"
    //   - extra věci, které jednotlivá stránka vystaví do window.MOTOGO_PAGE_CTX
    //     (např. shop-detail si tam může strčit produkt, blog-detail článek, atd.)
    function buildPageCtx() {
      try {
        var path = (location.pathname || '/').replace(/\/+$/, '') || '/';
        var type = 'other';
        var motoId = null, slug = null;
        // /katalog/<motoId>  (UUID nebo cokoliv co není prázdné)
        var mMoto = path.match(/^\/katalog\/([^\/]+)$/);
        if (mMoto) { type = 'moto_detail'; motoId = mMoto[1]; }
        else if (path === '/katalog') type = 'katalog';
        else if (path === '/' || path === '/home') type = 'home';
        else if (path === '/shop') type = 'shop';
        else { var mShop = path.match(/^\/shop\/([^\/]+)$/); if (mShop) { type = 'shop_detail'; slug = mShop[1]; } }
        if (type === 'other') {
          if (path === '/blog') type = 'blog';
          else { var mBlog = path.match(/^\/blog\/([^\/]+)$/); if (mBlog) { type = 'blog_detail'; slug = mBlog[1]; } }
        }
        if (type === 'other') {
          if (path === '/faq') type = 'faq';
          else if (path === '/kontakt') type = 'kontakt';
          else if (path === '/pujcovna') type = 'pujcovna';
          else if (path === '/partneri') type = 'partneri';
          else if (path === '/poukazy') type = 'poukazy';
          else if (path === '/poukazy-objednat') type = 'poukazy_objednat';
          else if (path.indexOf('/jak-pujcit') === 0) type = 'jak_pujcit';
          else if (path === '/rezervace') type = 'rezervace';
          else if (path === '/potvrzeni') type = 'potvrzeni';
        }
        // První H1 jako orientační název toho, na co se uživatel dívá
        var h1 = '';
        try {
          var h1El = document.querySelector('h1');
          if (h1El && h1El.textContent) h1 = h1El.textContent.replace(/\s+/g, ' ').trim().slice(0, 200);
        } catch (e) {}
        // Označený text — když uživatel něco vybere a zeptá se "co to znamená"
        var selection = '';
        try {
          if (window.getSelection) {
            var s = String(window.getSelection() || '').replace(/\s+/g, ' ').trim();
            if (s) selection = s.slice(0, 500);
          }
        } catch (e) {}
        var extra = (window.MOTOGO_PAGE_CTX && typeof window.MOTOGO_PAGE_CTX === 'object') ? window.MOTOGO_PAGE_CTX : null;
        return {
          url: location.href,
          path: path,
          type: type,
          title: (document.title || '').slice(0, 200),
          h1: h1,
          moto_id: motoId,
          slug: slug,
          selection: selection,
          extra: extra,
        };
      } catch (e) { return null; }
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
          body: JSON.stringify({ messages: conversation, lang: LANG, page_context: buildPageCtx() }),
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
