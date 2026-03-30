/* === UI-SOS-REPLACEMENT.JS — SOS replacement flow, payment & swap === */

// ===== SOS REPLACEMENT — přesměrování na Upravit rezervaci =====
var _sosReplacementMode = false;
var _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 0 };

var _sosReplacementLoading = false;
var _sosCurrentMotoId = null; // ID aktuální (rozbité) motorky zákazníka
function sosRequestReplacement() {
    if(_sosReplacementLoading) return; // guard against double-click
    _sosReplacementLoading = true;
    sosLoading();
    showT('⏳','Načítám...','Připravuji náhradní motorky');

    // Persist fault state so it survives async operations
    _sosFaultSnapshot = _sosFault;

    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – žádám náhradní motorku. ' + faultDesc;
    var type = _sosFault === true ? 'accident_major' : _sosFault === false ? 'accident_major' : 'breakdown_major';

    // Předem načti aktivní booking a ulož moto_id — MUSÍ se počkat než se vytvoří incident
    _sosCurrentMotoId = null;
    (async function(){
      try {
        var uid = null;
        try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}
        if(uid){
          // Hledej jakoukoliv aktivní/potvrzenou rezervaci, ne jen paid+active
          var bk = await window.supabase.from('bookings')
            .select('moto_id')
            .eq('user_id', uid)
            .in('status', ['active', 'pending', 'reserved'])
            .lte('start_date', new Date().toISOString())
            .gte('end_date', new Date().toISOString())
            .limit(1);
          if(bk.data && bk.data.length > 0 && bk.data[0].moto_id){
            _sosCurrentMotoId = bk.data[0].moto_id;
          }
        }
      } catch(e){ console.warn('[SOS] pre-fetch moto_id:', e); }

    // Teprve po načtení moto_id vytvoř/reuse incident
    var incId = await _sosEnsureIncident(type, desc);
      _sosReplacementLoading = false;
      sosLoadingHide();
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      _sosPendingIncidentId = incId;
      var upd = {customer_decision:'replacement_moto', moto_rideable:false, replacement_status: 'selecting'};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      // Ulož aktuální moto_id i do incidentu
      if(_sosCurrentMotoId) upd.original_moto_id = _sosCurrentMotoId;
      _sosUpdateIncident(incId, upd);
      // End original booking immediately — moto is not rideable, ride is over
      await _sosEndBooking(incId);
      _sosReplacementMode = true;
      // Přejdi na dedicated SOS replacement screen
      goTo('s-sos-replacement');
    })().catch(function(e){ console.error('[SOS] sosRequestReplacement:', e); _sosReplacementLoading = false; sosLoadingHide(); });
}

function sosReplInit(){
    // Reset state
    _sosReplacementData = { selectedMotoId: null, selectedModel: null, dailyPrice: 0, deliveryFee: 0 };

    // Restore from pending SOS incident if coming from floating banner
    if(window._pendingSosIncident && !_sosPendingIncidentId){
      var inc = window._pendingSosIncident;
      _sosPendingIncidentId = inc.id;
      // 3 paths: breakdown (null) = free, not-at-fault (false) = free, at-fault (true) = paid
      if(inc.customer_fault === true){
        _sosFault = true; _sosFaultSnapshot = true;
      } else {
        // breakdown (null) or not-at-fault (false) → both free
        _sosFault = inc.customer_fault === false ? false : null;
        _sosFaultSnapshot = _sosFault;
      }
      if(inc.original_moto_id) _sosCurrentMotoId = inc.original_moto_id;
    }

    // Use snapshot as fallback
    var isFault = _sosFault === true || _sosFaultSnapshot === true;
    var hdr = document.getElementById('sos-repl-hdr');
    var sub = document.getElementById('sos-repl-subtitle');
    var banner = document.getElementById('sos-repl-banner');
    var totalLabel = document.getElementById('sos-repl-total-label');
    var totalEl = document.getElementById('sos-repl-total');
    var btn = document.getElementById('sos-repl-btn');

    if(isFault){
      if(hdr) hdr.style.background = 'linear-gradient(135deg,#7f1d1d,#b91c1c)';
      if(sub) sub.textContent = 'Zaviněná nehoda — náhradní motorka za poplatek';
      if(banner){
        banner.style.background = '#fee2e2';
        banner.style.border = '1px solid #fca5a5';
        banner.style.color = '#b91c1c';
        banner.innerHTML = '⚠️ Nehoda zaviněná zákazníkem — motorka a přistavení jsou <strong>za poplatek</strong>. Po zaplacení bude motorka ihned přistavena.';
      }
      if(btn){
        btn.style.background = '#b91c1c';
        btn.textContent = '💳 Zaplatit a objednat motorku';
      }
    } else {
      if(hdr) hdr.style.background = 'linear-gradient(135deg,#1a2e22,#2d5a3c)';
      if(sub) sub.textContent = 'Porucha / nezaviněná nehoda — přistavení zdarma';
      if(banner){
        banner.style.background = 'var(--gp)';
        banner.style.border = '1px solid var(--green)';
        banner.style.color = 'var(--gd)';
        banner.innerHTML = '💚 Náhradní motorka i přistavení jsou <strong>zdarma</strong> (porucha / nezaviněná nehoda).';
      }
      if(totalEl){ totalEl.textContent = '0 Kč'; totalEl.style.color = 'var(--green)'; }
      if(totalLabel) totalLabel.style.color = 'var(--green)';
      if(btn){
        btn.style.background = 'var(--green)';
        btn.textContent = '✅ Potvrdit objednávku (zdarma)';
      }
    }

    // Načti dostupné motorky
    sosReplLoadMotos();
}

async function sosReplLoadMotos(){
    var container = document.getElementById('sos-repl-motos');
    if(!container) return;
    sosLoading();
    container.innerHTML = '<div style="text-align:center;padding:15px;color:var(--g400);font-size:12px;">⏳ Načítám dostupné motorky...</div>';

    try {
      // Zjisti uživatele
      var uid = null;
      try { var u = await window.supabase.auth.getUser(); uid = u.data && u.data.user ? u.data.user.id : null; } catch(e){}

      // Najdi aktivní rezervaci — širší dotaz než apiGetActiveLoan (zahrnuje i confirmed/pending)
      var startDate = null, endDate = null, currentMotoId = _sosCurrentMotoId || null;
      if(uid){
        var bkR = await window.supabase.from('bookings')
          .select('moto_id, start_date, end_date')
          .eq('user_id', uid)
          .in('status', ['active', 'pending', 'reserved'])
          .lte('start_date', new Date().toISOString())
          .gte('end_date', new Date().toISOString())
          .limit(1);
        if(bkR.data && bkR.data.length > 0){
          var bk = bkR.data[0];
          startDate = bk.start_date;
          endDate = bk.end_date;
          if(!currentMotoId) currentMotoId = bk.moto_id;
        }
      }
      // Záloha: zkus i apiGetActiveLoan
      if(!currentMotoId){
        var loan = await apiGetActiveLoan();
        if(loan){
          if(!startDate) startDate = loan.start_date;
          if(!endDate) endDate = loan.end_date;
          currentMotoId = loan.moto_id;
        }
      }
      // Zjisti řidičák zákazníka
      var customerLicense = null;
      if(uid){
        var pr = await window.supabase.from('profiles').select('license_group').eq('id', uid).single();
        if(pr.data && pr.data.license_group) customerLicense = pr.data.license_group; // array e.g. ['A'] or ['A2']
      }

      // Načti všechny motorky se statusem active
      var r = await window.supabase.from('motorcycles')
        .select('id, model, image_url, images, price_weekday, price_weekend, category, license_required, branches(name, city)')
        .eq('status', 'active')
        .limit(50);
      var allMotos = r.data || [];

      // Načti motorky s rezervacemi překrývajícími zbývající období (dnes → konec původní rezervace)
      var rentedMotoIds = {};
      var nowISO = new Date().toISOString().slice(0,10);
      var overlapEnd = endDate || nowISO; // end_date původní rezervace = konec období náhradní motorky
      try {
        // Najdi všechny bookings které se překrývají s obdobím [dnes, endDate]
        // Překryv: booking.start_date <= overlapEnd AND booking.end_date >= nowISO
        var rentedR = await window.supabase.from('bookings')
          .select('moto_id')
          .in('status', ['active', 'reserved', 'pending'])
          .lte('start_date', overlapEnd)
          .gte('end_date', nowISO);
        if(rentedR.data){
          rentedR.data.forEach(function(b){ if(b.moto_id) rentedMotoIds[String(b.moto_id).toLowerCase()] = true; });
        }
      } catch(e){ console.warn('[SOS] fetch rented motos:', e); }

      // Hierarchie ŘP skupin: A > A2 > A1 > AM, B samostatně, N = bez ŘP
      // Skupina A smí řídit: A, A2, A1, AM
      // Skupina A2 smí řídit: A2, A1, AM
      // Skupina A1 smí řídit: A1, AM
      // Skupina AM smí řídit: AM
      // Skupina B smí řídit: B, AM
      // N = nevyžaduje ŘP (dětské motorky) — může kdokoliv
      var LICENSE_COVERS = {
        'A':  ['A','A2','A1','AM'],
        'A2': ['A2','A1','AM'],
        'A1': ['A1','AM'],
        'AM': ['AM'],
        'B':  ['B','AM']
      };

      // Filtruj: 1) ne aktuální motorku, 2) ne motorky s překrývající rezervací, 3) řidičák
      var motos = allMotos.filter(function(m){
        var motoIdLower = String(m.id).toLowerCase();
        // Vyřaď aktuální (rozbitou) motorku zákazníka
        if(currentMotoId && motoIdLower === String(currentMotoId).toLowerCase()) return false;
        // Vyřaď motorky s překrývající rezervací v období náhradní motorky
        if(rentedMotoIds[motoIdLower]) return false;
        // Řidičák — motorky s N (dětské) může řídit kdokoliv
        var req = m.license_required;
        if(!req || req === 'N') return true;
        if(!customerLicense) return true; // nemáme info → zobraz vše
        var has = Array.isArray(customerLicense) ? customerLicense : [customerLicense];
        // Zákazník smí řídit motorku pokud některá jeho skupina pokrývá požadovanou
        var canRide = false;
        for(var i = 0; i < has.length; i++){
          var covers = LICENSE_COVERS[has[i]];
          if(covers && covers.indexOf(req) !== -1){ canRide = true; break; }
        }
        return canRide;
      });
      if(motos.length === 0){
        container.innerHTML = '<div style="text-align:center;padding:15px;color:#b91c1c;font-size:12px;font-weight:600;">Žádné motorky momentálně nejsou dostupné. Kontaktujte MotoGo24.</div>';
        return;
      }

      // Spočítej zbývající dny pro cenový výpočet
      var remainingDays = 1;
      if(endDate){
        var now2 = new Date();
        var end2 = new Date(endDate);
        remainingDays = Math.max(1, Math.ceil((end2 - now2) / (1000*60*60*24)));
      }
      _sosReplacementData._remainingDays = remainingDays;
      _sosReplacementData._endDate = endDate;

      var isFault = _sosFault === true || _sosFaultSnapshot === true;
      var html = '';
      motos.forEach(function(m){
        var price = parseFloat(m.price_weekday) || parseFloat(m.price_weekend) || 890;
        var img = m.image_url || (m.images && m.images[0]) || '';
        var branch = m.branches ? (m.branches.name || m.branches.city || '') : '';
        html += '<div class="sos-repl-moto-card" onclick="sosReplSelectMoto(\'' + m.id + '\',\'' + (m.model||'').replace(/'/g,"\\'") + '\',' + price + ')" '
          + 'id="sos-moto-' + m.id + '" '
          + 'style="display:flex;align-items:center;gap:12px;padding:10px;border:2px solid var(--g200);border-radius:var(--rsm);cursor:pointer;transition:all .15s;">'
          + (img ? '<img src="' + img + '" style="width:56px;height:40px;object-fit:cover;border-radius:8px;flex-shrink:0;" alt="">' : '<div style="width:56px;height:40px;background:var(--g100);border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0;">🏍️</div>')
          + '<div style="flex:1;min-width:0;">'
          + '<div style="font-size:13px;font-weight:800;color:var(--black);">' + (m.model||'Motorka') + '</div>'
          + '<div style="font-size:10px;color:var(--g400);margin-top:1px;">' + branch + (endDate ? ' · do ' + new Date(endDate).toLocaleDateString('cs-CZ') : '') + '</div>'
          + '</div>'
          + '<div style="text-align:right;">'
          + '<div style="font-size:12px;font-weight:800;color:var(--black);">' + price.toLocaleString('cs-CZ') + ' Kč/den</div>'
          + (isFault ? '<div style="font-size:10px;color:var(--g400);">' + remainingDays + ' ' + (remainingDays === 1 ? 'den' : remainingDays < 5 ? 'dny' : 'dní') + ' = ' + (price * remainingDays).toLocaleString('cs-CZ') + ' Kč</div>' : '')
          + '</div>'
          + '</div>';
      });
      container.innerHTML = html;
      sosLoadingHide();
    } catch(e){
      sosLoadingHide();
      container.innerHTML = '<div style="text-align:center;padding:15px;color:#b91c1c;font-size:12px;font-weight:600;">Chyba při načítání motorek.</div>';
      console.error('[SOS] loadMotos:', e);
    }
}

