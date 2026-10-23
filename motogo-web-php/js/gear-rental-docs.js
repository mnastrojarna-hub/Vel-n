/* MotoGo24 — Půjčení výbavy: nahrání dokladu totožnosti po zaplacení (2026-10-23).
   U výbavy stačí doklad totožnosti — občanka (přední + zadní strana) NEBO pas — a věk 18+
   (datum narození); řidičák ne (booking_docs_gate, pravidlo pro gear). Stejný mechanismus jako
   motorkový web: fotka / PDF → edge save-verification-document (oprávnění = booking_id živé
   rezervace, přihlášený navíc JWT), datum narození → set_web_booking_docs, dokončení →
   set_web_booking_docs_completed; co ještě chybí vrací get_web_gear_booking.docs.missing. */
(function () {
  var G = window.MGGR;
  if (!G) return;
  var T = G.T, esc = G.esc, q = G.q, MAX = 8388608;

  // docs.missing (česky z _docs_gate_checklist, případně klíče) → co ještě chybí
  function need(miss) {
    var r = { files: false, front: false, back: false, dob: false, age: false, other: [] };
    (Array.isArray(miss) ? miss : []).forEach(function (m) {
      var s = String((m && typeof m === 'object' ? (m.key || m.code || m.label) : m) || '');
      if (/naroz|birth|dob/i.test(s)) r.dob = true;
      else if (/18|věk|\bage\b|nesplňují/i.test(s)) r.age = true;
      else if (/líc a rub|nebo pas|identit|passport/i.test(s)) r.files = true;
      else if (/\brub\b|back/i.test(s)) r.back = true;
      else if (/líc|front/i.test(s)) r.front = true;
      else if (/\bOP\b|pas|doklad|id_card/i.test(s)) r.files = true;
      else if (s) r.other.push(s);
    });
    if (!r.files && !r.front && !r.back && !r.dob && !r.age && !r.other.length) { r.files = true; r.dob = true; }
    return r;
  }
  function needText(r) {
    var a = [];
    if (r.files) a.push(T.docs_need_files);
    if (r.front) a.push(T.docs_need_front);
    if (r.back) a.push(T.docs_need_back);
    if (r.dob) a.push(T.docs_need_dob);
    if (r.age) a.push(T.docs_age);
    return a.concat(r.other).join(' ');
  }
  function slot(type, side, label, done) {
    var k = type + (side ? '-' + side : '');
    return '<div class="gr-slot' + (done ? ' is-done' : '') + '" data-slot="' + k + '"><span class="gr-slot-t">' + esc(label) + '</span>' +
      '<label class="gr-slot-btn"><input type="file" class="gr-file" accept="image/*,application/pdf" data-type="' + type + '" data-side="' + (side || '') + '">' +
      '<span>' + esc(done ? T.docs_again : T.docs_pick) + '</span></label><span class="gr-slot-s" data-st aria-live="polite">' + (done ? '✔ ' + esc(T.docs_done) : '') + '</span></div>';
  }
  function adultMax() {
    var t = G.K.today();
    return (+t.slice(0, 4) - 18) + t.slice(4);
  }

  G.docsHtml = function (o) {
    var r = need(o.docs && o.docs.missing), self = o.branch && o.branch.type === 'samoobslužná', files = r.files || r.front || r.back;
    return '<section class="gr-docs" id="gr-docs" data-gr-docs><h3>' + esc(T.docs_title) + '</h3><p>' + esc(T.docs_lead) + ' ' + esc(self ? T.docs_self : T.docs_staffed) + '</p>' +
      (files ? '<div class="gr-docs-mode" role="radiogroup" aria-label="' + esc(T.docs_title) + '"><label><input type="radio" name="gr-dmode" value="id" checked> ' + esc(T.docs_id) + '</label>' +
        '<label><input type="radio" name="gr-dmode" value="passport"> ' + esc(T.docs_pass) + '</label></div>' +
        '<div class="gr-slots" data-mode="id">' + slot('id', 'front', T.docs_front, r.back && !r.front && !r.files) + slot('id', 'back', T.docs_back, r.front && !r.back && !r.files) + '</div>' +
        '<div class="gr-slots" data-mode="passport" hidden>' + slot('passport', '', T.docs_page, false) + '</div>' : '') +
      (r.dob || r.age ? '<label class="gr-dob"><span>' + esc(T.docs_dob) + '</span><input type="date" id="gr-dob" min="1900-01-01" max="' + adultMax() + '" autocomplete="bday"></label>' : '') +
      '<p class="gr-docs-msg" data-gr-dmsg role="status" hidden></p>' +
      '<button type="button" class="lp-btn lp-btn-primary gr-docs-send" data-gr-dsend>' + G.K.ico('check') + '<span>' + esc(T.docs_submit) + '</span></button>' +
      '<p class="gr-docs-later">' + esc(T.docs_later) + '</p></section>';
  };

  function readUrl(file) {
    return new Promise(function (ok, ko) {
      var fr = new FileReader();
      fr.onload = function () { ok(String(fr.result || '')); };
      fr.onerror = function () { ko(fr.error || new Error('read')); };
      fr.readAsDataURL(file);
    });
  }
  // Fotka → JPEG max. 2200 px (telefonní fotky mívají přes 8 MB); PDF beze změny
  function jpeg(file) {
    return new Promise(function (ok, ko) {
      var url = URL.createObjectURL(file), img = new Image();
      img.onload = function () {
        try {
          var r = Math.min(1, 2200 / Math.max(img.naturalWidth, img.naturalHeight)), c = document.createElement('canvas');
          c.width = Math.max(1, Math.round(img.naturalWidth * r)); c.height = Math.max(1, Math.round(img.naturalHeight * r));
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          URL.revokeObjectURL(url); ok(c.toDataURL('image/jpeg', 0.86));
        } catch (e) { URL.revokeObjectURL(url); ko(e); }
      };
      img.onerror = function () { URL.revokeObjectURL(url); ko(new Error('img')); };
      img.src = url;
    });
  }
  function payload(file) {
    var t = String(file.type || '').toLowerCase();
    if (!t && /\.pdf$/i.test(file.name || '')) t = 'application/pdf';
    if (t === 'application/pdf') return file.size > 0 && file.size <= MAX ? readUrl(file).then(function (b) { return { b: b, mime: t }; }) : Promise.reject(new Error('size'));
    return jpeg(file).then(function (b) { return { b: b, mime: 'image/jpeg' }; }, function () {
      if (['image/jpeg', 'image/png', 'image/webp'].indexOf(t) >= 0 && file.size <= MAX) return readUrl(file).then(function (b) { return { b: b, mime: t }; });
      throw new Error('type');
    });
  }

  // Obsluha karty: nahrání po slotech, odeslání, nový stav z get_web_gear_booking
  G.docsBind = function (box, o, session) {
    var sec = q('[data-gr-docs]', box);
    if (!sec) return;
    var up = {}, mode = 'id', dm = q('[data-gr-dmsg]', sec);
    Array.prototype.forEach.call(sec.querySelectorAll('.gr-slot.is-done'), function (s) { up[s.getAttribute('data-slot')] = true; });
    function say(t, ok) { dm.textContent = t || ''; dm.hidden = !t; dm.classList.toggle('is-ok', !!ok); }
    sec.addEventListener('change', function (ev) {
      var t = ev.target;
      if (t.name === 'gr-dmode') {
        mode = t.value;
        Array.prototype.forEach.call(sec.querySelectorAll('.gr-slots'), function (g) { g.hidden = g.getAttribute('data-mode') !== mode; });
        return;
      }
      if (!t.files || !t.files[0]) return;
      var type = t.getAttribute('data-type'), side = t.getAttribute('data-side') || '', k = type + (side ? '-' + side : '');
      var sl = q('[data-slot="' + k + '"]', sec), stt = q('[data-st]', sl), file = t.files[0];
      sl.classList.remove('is-done', 'is-bad'); stt.textContent = T.docs_busy; say('');
      payload(file).then(function (p) {
        return G.edge('save-verification-document', { booking_id: o.id, doc_type: type, image_base64: p.b, mindee_status: 'failed', mime: p.mime, doc_side: side || null }, true);
      }).then(function (r) {
        if (!(r && r.success && r.document_id)) throw new Error('save');
        up[k] = true; sl.classList.add('is-done'); stt.textContent = '✔ ' + T.docs_done;
        q('.gr-slot-btn span', sl).textContent = T.docs_again;
      }).catch(function () {
        delete up[k]; sl.classList.add('is-bad'); stt.textContent = T.docs_err;
      }).then(function () { t.value = ''; });
    });
    q('[data-gr-dsend]', sec).addEventListener('click', function () {
      var b = this, dob = q('#gr-dob', sec), hasFiles = !!q('.gr-slots', sec);
      if (hasFiles && !(mode === 'passport' ? up.passport : up['id-front'] && up['id-back'])) return say(T.docs_need_files);
      if (dob && !dob.value) return say(T.docs_need_dob);
      var lbl = b.innerHTML;
      b.disabled = true; b.innerHTML = '<span>' + esc(T.docs_checking) + '</span>'; say('');
      (dob ? G.rpc('set_web_booking_docs', { p_booking_id: o.id, p_date_of_birth: dob.value }) : Promise.resolve(null))
        .then(function () { return G.rpc('set_web_booking_docs_completed', { p_booking_id: o.id }); })
        .then(function () { return G.rpc('get_web_gear_booking', { p_booking_id: o.id, p_session_id: session || null }); })
        .then(function (f) {
          b.disabled = false; b.innerHTML = lbl;
          var dd = f && !f.error && f.docs;
          if (dd && dd.ok) {
            sec.innerHTML = '<h3>' + esc(T.docs_title) + '</h3><p class="gr-docs-msg is-ok" role="status">✔ ' + esc(T.docs_ok) + '</p>';
            return;
          }
          say(dd ? needText(need(dd.missing)) : T.err_server);
        }).catch(function () { b.disabled = false; b.innerHTML = lbl; say(T.err_server); });
    });
  };
})();
