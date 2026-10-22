/* MotoGo24 — Půjčení výbavy: přihlášení existujícího zákazníka (2026-10-23).
   create_web_gear_booking vrátí u e-mailu s účtem `email_exists` → panel pod souhrnem:
   heslo (signInWithPassword) nebo zapomenuté heslo jako motorkový web (edge send-recovery-otp
   → kód z e-mailu + nové heslo, verifyOtp + updateUser). Po přihlášení se rezervace odešle
   znovu, už s JWT. Uložená session = řádek „Přihlášen(a) jako …“ (+ Odhlásit) a předvyplnění
   prázdných polí kontaktu z profilu. Supabase SDK se načítá až tady (MGGR.loadSb).
   Panel leží UVNITŘ formuláře rezervace → vlastní <form> nejde (vnořený formulář prohlížeč
   zahodí); „formuláře“ panelu jsou <div data-f>, odeslání tlačítkem nebo Enterem. */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var C = G.C, T = G.T, esc = G.esc, q = G.q, again = null, otpMail = '';
  G.user = null;

  function inp(type, name, ph, extra) {
    return '<input type="' + type + '" name="' + name + '" placeholder="' + esc(ph) + '" aria-label="' + esc(ph) + '"' + (extra || '') + '>';
  }
  function card(v, title, help, form, back) {
    return '<div class="gr-login-card" data-v="' + v + '"' + (v === 'login' ? '' : ' hidden') + '><h3>' + esc(title) + '</h3><p data-help>' + esc(help) + '</p>' +
      '<div class="gr-login-form" data-f="' + v + '">' + form + '</div><p class="gr-login-msg" data-m role="alert" hidden></p>' +
      '<p><button type="button" class="gr-linkbtn" data-go="' + (back ? 'login' : 'forgot') + '">' + esc(back ? T.login_back : T.login_forgot) + '</button></p></div>';
  }
  function html(email) {
    var em = inp('email', 'email', T.email, ' required autocomplete="email" inputmode="email" value="' + esc(email) + '"');
    return card('login', T.login_title, T.login_help, em + inp('password', 'password', T.login_password, ' required autocomplete="current-password"') +
        '<button type="button" class="lp-btn lp-btn-primary" data-submit>' + esc(T.login_submit) + '</button>', false) +
      card('forgot', T.login_forgot, T.forgot_help, em + '<button type="button" class="lp-btn lp-btn-primary" data-submit>' + esc(T.forgot_send) + '</button>', true) +
      card('otp', T.login_forgot, '', inp('text', 'code', T.forgot_code, ' required autocomplete="one-time-code" maxlength="10" class="gr-otp"') +
        inp('password', 'pw1', T.forgot_pw, ' required autocomplete="new-password" minlength="8"') + inp('password', 'pw2', T.forgot_pw2, ' required autocomplete="new-password" minlength="8"') +
        '<button type="button" class="lp-btn lp-btn-primary" data-submit>' + esc(T.forgot_submit) + '</button>', true);
  }
  function box() { return q('[data-gr-login]'); }
  function view(v) {
    Array.prototype.forEach.call(box().querySelectorAll('[data-v]'), function (c) { c.hidden = c.getAttribute('data-v') !== v; });
    var f = box().querySelector('[data-v="' + v + '"] input:not([type=email])') || box().querySelector('[data-v="' + v + '"] input');
    try { f && f.focus(); } catch (e) {}
  }
  function msg(f, t, ok) {
    var m = f.parentNode.querySelector('[data-m]');
    m.textContent = t || ''; m.hidden = !t; m.classList.toggle('is-ok', !!ok);
  }
  function val(f, n) { var e = f.querySelector('[name="' + n + '"]'); return e ? String(e.value || '') : ''; }
  function busy(f, on, label) {
    var b = f.querySelector('[data-submit]');
    if (on) { b._t = b.textContent; b.textContent = label; } else if (b._t) b.textContent = b._t;
    b.disabled = !!on;
  }

  // Zobrazí panel (e-mail z formuláře) a po přihlášení zavolá `retry`
  G.showLogin = function (email, retry) {
    var b = box();
    if (!b) return;
    again = retry || null;
    b.innerHTML = html(email || '');
    b.hidden = false;
    try { b.scrollIntoView({ behavior: 'smooth', block: 'center' }); } catch (e) {}
    setTimeout(function () { view('login'); }, 250);
  };

  function after(user) {
    G.user = user;
    var b = box();
    if (b) { b.hidden = true; b.innerHTML = ''; }
    var em = q('#gr-email');
    if (em && user.email) em.value = user.email;
    authLine();
    return prefill(user).then(function () { var r = again; again = null; if (r) r(); });
  }
  function login(f) {
    var em = val(f, 'email').trim().toLowerCase(), pw = val(f, 'password');
    if (!em || !pw) return msg(f, T.login_err);
    busy(f, true, T.login_busy); msg(f, '');
    G.loadSb().then(function (sb) { return sb.auth.signInWithPassword({ email: em, password: pw }); }).then(function (r) {
      busy(f, false);
      if (r.error || !r.data || !r.data.user) return msg(f, T.login_err);
      return after(r.data.user);
    }).catch(function () { busy(f, false); msg(f, T.err_server); });
  }
  function forgot(f) {
    var em = val(f, 'email').trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) return msg(f, T.err_contact);
    busy(f, true, T.forgot_busy);
    G.edge('send-recovery-otp', { email: em, language: C.lang }).then(function (r) {
      busy(f, false);
      if (r._status >= 500) return msg(f, T.err_server);
      otpMail = em;
      box().querySelector('[data-v="otp"] [data-help]').textContent = G.tpl(T.forgot_sent, { email: em });
      view('otp');
    }).catch(function () { busy(f, false); msg(f, T.err_server); });
  }
  function otp(f) {
    var code = val(f, 'code').replace(/\s+/g, '').toUpperCase(), p1 = val(f, 'pw1'), p2 = val(f, 'pw2');
    if (code.length < 6) return msg(f, T.forgot_err_code);
    if (p1.length < 8 || p1 !== p2) return msg(f, T.forgot_err_pw);
    busy(f, true, T.login_busy);
    var sb;
    G.loadSb().then(function (s) { sb = s; return sb.auth.verifyOtp({ email: otpMail, token: code, type: 'recovery' }); }).then(function (r) {
      if (r.error || !r.data || !r.data.session) { busy(f, false); return msg(f, T.forgot_err_code); }
      return sb.auth.updateUser({ password: p1 }).then(function (u) {
        busy(f, false);
        if (u.error) {
          var m = String(u.error.message || u.error.code || '').toLowerCase();
          return msg(f, m.indexOf('different from the old') >= 0 || m.indexOf('same_password') >= 0 ? T.forgot_err_same : T.err_server);
        }
        return after((u.data && u.data.user) || r.data.user);
      });
    }).catch(function () { busy(f, false); msg(f, T.err_server); });
  }

  // ---- řádek „Přihlášen(a) jako …“ + předvyplnění ----
  function authLine() {
    var el = q('[data-gr-authline]');
    if (!el) return;
    el.hidden = !G.user;
    el.innerHTML = G.user ? '<span>' + esc(G.tpl(T.logged_as, { email: G.user.email || '' })) + '</span> <button type="button" class="gr-linkbtn" data-gr-logout>' + esc(T.logout) + '</button>' : '';
  }
  function prefill(user) {
    if (!window.sb) return Promise.resolve();
    return window.sb.from('profiles').select('full_name,email,phone,street,city,zip,company_name,ico,dic').eq('id', user.id).maybeSingle().then(function (r) {
      var p = (r && r.data) || {};
      var set = function (id, v) { var e = q('#' + id); if (e && v && !String(e.value || '').trim()) e.value = v; };
      set('gr-name', p.full_name); set('gr-email', p.email || user.email); set('gr-phone', p.phone);
      set('gr-street', p.street); set('gr-zip', p.zip); set('gr-city', p.city);
      if (p.company_name || p.ico) {
        var co = q('#gr-company-on');
        if (co && !co.checked) { co.checked = true; q('#gr-company').hidden = false; }
        set('gr-company-name', p.company_name); set('gr-ico', p.ico); set('gr-dic', p.dic);
      }
    }).catch(function () {});
  }
  G.authInit = function () {
    var lb = box();
    if (lb) {
      var send = function (f) {
        var v = f.getAttribute('data-f');
        if (v === 'login') login(f); else if (v === 'forgot') forgot(f); else if (v === 'otp') otp(f);
      };
      lb.addEventListener('click', function (ev) {
        var b = ev.target.closest('[data-go]'), s = ev.target.closest('[data-submit]');
        if (b) view(b.getAttribute('data-go'));
        else if (s && !s.disabled) send(s.closest('[data-f]'));
      });
      // Enter v panelu = odeslat panel (ne celý formulář rezervace)
      lb.addEventListener('keydown', function (ev) {
        if (ev.key !== 'Enter' || ev.target.tagName !== 'INPUT') return;
        ev.preventDefault();
        var f = ev.target.closest('[data-f]'), s = f && f.querySelector('[data-submit]');
        if (s && !s.disabled) send(f);
      });
    }
    var al = q('[data-gr-authline]');
    al && al.addEventListener('click', function (ev) {
      if (!ev.target.closest('[data-gr-logout]')) return;
      G.loadSb().then(function (sb) { return sb.auth.signOut(); }).catch(function () {}).then(function () { G.user = null; authLine(); });
    });
    if (!G.hasStored()) return;
    G.session().then(function (s) {
      if (!s || !s.user) return;
      G.user = s.user; authLine(); prefill(s.user);
    });
  };
})();
