/* === UI-SOS-COMPLETION.JS — SOS end ride, AI chat, photos & voice === */

function sosEndRide() {
    showT('🚛', 'Objednávám odtah...', '');
    sosLoading();
    // Keep _sosActiveIncidentId — reuse existing incident from sosReportAccident
    var faultDesc = _sosFault === true ? 'Nehoda byla moje chyba' : _sosFault === false ? 'Nehoda nebyla moje chyba' : '';
    var desc = 'Motorka nepojízdná – ukončuji jízdu, žádám odtah. ' + faultDesc;
    var type = _sosFault !== null ? 'accident_major' : 'breakdown_major';
    _sosEnsureIncident(type, desc).then(function(incId){
      if(!incId){ showT('❌','Chyba','Nepodařilo se nahlásit incident'); return; }
      var upd = {customer_decision:'end_ride', moto_rideable:false};
      if(_sosFault !== null) upd.customer_fault = _sosFault;
      _sosUpdateIncident(incId, upd);
      // Mark booking as completed + ended_by_sos
      _sosEndBooking(incId);
      apiSosRequestTow(incId).then(function(){
        // Timeline entry s detaily
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — žádá odtah' + (_sosFault === true ? ' (zavinil zákazník)' : _sosFault === false ? ' (cizí zavinění — zdarma)' : ''),
        }).then(function(){});
        sosLoadingHide();
        _sosShowDone('Odtah objednán', 'MotoGo24 zařídí odtah motorky. Asistent vás bude kontaktovat.',
          '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>');
      });
    });
}

function sosEndRideFree() {
    // Keep _sosActiveIncidentId — reuse existing incident
    sosLoading();
    var desc = 'Porucha – motorka nepojízdná. Ukončuji jízdu, zařídím se sám.';
    _sosEnsureIncident('breakdown_major', desc).then(function(incId){
      if(incId){
        _sosUpdateIncident(incId, {customer_decision:'end_ride', moto_rideable:false, customer_fault:false});
        // Mark booking as completed + ended_by_sos
        _sosEndBooking(incId);
        apiSosRequestTow(incId);
        // Timeline entry
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník ukončuje jízdu — porucha (nezaviněná) — pronájem zdarma, odtah objednán',
        }).then(function(){});
      }
      sosLoadingHide();
      _sosShowDone('Pronájem zdarma', 'Vracíme plnou částku. Odtah zajistíme.',
        '<button onclick="goTo(\'s-res\')" style="width:100%;background:var(--green);color:#fff;border:none;border-radius:50px;padding:14px;font-family:var(--font);font-size:14px;font-weight:800;cursor:pointer;">📋 Zobrazit moje rezervace</button>');
    });
}

function sosShareLocation() {
    if (!navigator.geolocation) { showT('❌', 'GPS nedostupné', 'Váš prohlížeč nepodporuje GPS'); return; }
    showT('📍', 'Zjišťuji polohu...', 'Čekejte prosím');

    function _sendLocation(lat, lng) {
        apiGetMySosIncidents().then(function(incidents) {
            var latest = incidents && incidents.length ? incidents[0] : null;
            if (latest) {
                apiSosShareLocation(latest.id, lat, lng).then(function() {
                    showT('📍', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                });
            } else {
                apiGetActiveLoan().then(function(loan) {
                    var loanId = loan ? loan.id : null;
                    apiCreateSosIncident('location_share', loanId, lat, lng, null, null).then(function() {
                        showT('📍', 'Poloha sdílena MotoGo24', lat.toFixed(5) + ', ' + lng.toFixed(5));
                    });
                });
            }
        });
    }

    // Try high accuracy first, fallback to low accuracy on timeout
    navigator.geolocation.getCurrentPosition(
        function(pos) { _sendLocation(pos.coords.latitude, pos.coords.longitude); },
        function(err) {
            if (err.code === 1) { showT('❌', 'Přístup odepřen', 'Povolte polohu v nastavení'); return; }
            showT('📍', 'Hledám polohu...', 'Zkouším alternativní metodu');
            navigator.geolocation.getCurrentPosition(
                function(pos) { _sendLocation(pos.coords.latitude, pos.coords.longitude); },
                function(err2) {
                    if (err2.code === 1) showT('❌', 'Přístup odepřen', 'Povolte polohu v nastavení');
                    else if (err2.code === 2) showT('❌', 'GPS nedostupné', 'Zkuste to venku nebo povolte polohu');
                    else showT('❌', 'Časový limit', 'GPS neodpovědělo – zkuste to venku');
                },
                { enableHighAccuracy: false, timeout: 30000, maximumAge: 60000 }
            );
        },
        { enableHighAccuracy: true, timeout: 30000, maximumAge: 0 }
    );
}

function sosDrobnaZavada() {
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    sosLoading();
    showT('🔩', 'Hlásím závadu...', '');
    _sosActiveIncidentId = null;
    _sosFault = null;
    _sosEnsureIncident('breakdown_minor', 'Drobná závada – motorka pojízdná, pokračuji v jízdě').then(function(incId){
      _sosSubmitting = false;
      sosLoadingHide();
      if(incId){
        _sosUpdateIncident(incId, { moto_rideable: true, customer_fault: false, customer_decision: 'continue' });
        // Upload SOS photos if any
        if(typeof _sosPhotos!=='undefined' && _sosPhotos.length > 0) {
          uploadSOSPhotos(incId, _sosPhotos).then(function(urls){ if(urls.length) saveSOSPhotoUrls(incId, urls); _sosResetPhotos(); });
        }
        window.supabase.from('sos_timeline').insert({
          incident_id: incId,
          action: 'Zákazník nahlásil drobnou závadu — motorka pojízdná, pokračuje v jízdě',
        }).then(function(){});
      }
      _sosShowDone('Drobná závada', 'Děkujeme za nahlášení. Šťastnou cestu!');
    }).catch(function(){ _sosSubmitting = false; sosLoadingHide(); });
}

// ===== SOS PHOTO-ONLY SUBMIT — informativní fotodokumentace =====
function sosSubmitPhotosOnly() {
    if(typeof _sosPhotos==='undefined' || _sosPhotos.length === 0) {
      showT('⚠️', 'Žádné fotky', 'Nejdříve přidejte alespoň jednu fotku');
      return;
    }
    if(_sosSubmitting) return;
    _sosSubmitting = true;
    sosLoading();
    var btn = document.getElementById('sos-photo-submit-btn');
    if(btn){ btn.textContent = '⏳ Odesílám...'; btn.disabled = true; }
    // Get active booking for linking
    _sosPreFetchIds();
    setTimeout(function(){
      var bookingId = _sosCurrentBookingId || null;
      var motoId = _sosCurrentMotoId || null;
      // Create a lightweight 'other' incident for informative photo documentation
      _sosGetGPS().then(function(gps){
        return apiCreateSosIncident('other', bookingId, gps.lat, gps.lng, 'Informativní fotodokumentace – zákazník odeslal fotky', false, motoId);
      }).then(function(incId){
        if(!incId){
          _sosSubmitting = false;
          if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; }
          showT('❌', 'Chyba', 'Nepodařilo se odeslat. Zkuste znovu.');
          return;
        }
        // Upload photos
        uploadSOSPhotos(incId, _sosPhotos).then(function(urls){
          if(urls.length) saveSOSPhotoUrls(incId, urls);
          _sosResetPhotos();
          _sosSubmitting = false;
          sosLoadingHide();
          // Timeline entry
          window.supabase.from('sos_timeline').insert({
            incident_id: incId,
            action: 'Zákazník odeslal informativní fotodokumentaci (' + urls.length + ' fotek)',
          }).then(function(){});
          showT('✅', 'Fotodokumentace odeslána', 'MotoGo24 obdržela vaše fotky');
          if(btn){ btn.textContent = '✅ Odesláno'; btn.style.background = '#1a8a18'; btn.style.opacity = '0.8'; }
          setTimeout(function(){
            if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; btn.style.background = 'var(--green)'; btn.style.opacity = '1'; btn.style.display = 'none'; }
          }, 3000);
        });
      }).catch(function(e){
        console.error('[SOS] sosSubmitPhotosOnly error:', e);
        _sosSubmitting = false;
        sosLoadingHide();
        if(btn){ btn.textContent = '📤 Odeslat fotodokumentaci do MotoGo24'; btn.disabled = false; }
        showT('❌', 'Chyba', 'Nepodařilo se odeslat fotky');
      });
    }, 300);
}

// ===== AI CHAT =====
function aiGetResponse(txt){
  const lc=txt.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  // scan knowledge base
  for(const entry of AI_KB){
    for(const key of entry.keys){
      const kn=key.normalize('NFD').replace(/[\u0300-\u036f]/g,'');
      if(lc.includes(kn)) return entry.ans;
    }
  }
  return 'Rozumím. Pro tento problém doporučuji otevřít manuál v detailu motorky, nebo kontaktujte naši linku +420 774 256 271. Jsme tu 24/7! Zkuste popsat konkrétněji – např. "červená kontrolka", "kde je baterie BMW", "nechce nastartovat".';
}
function aiSend(textOverride){
  const inp=document.getElementById('ai-chat-inp');
  const msgs=document.getElementById('ai-chat-msgs');
  if(!msgs)return;
  const txt=(textOverride||inp?.value||'').trim();
  if(!txt)return;
  msgs.innerHTML+=`<div class="ai-msg user"><div class="ai-bubble">${txt}</div></div>`;
  if(inp)inp.value='';
  msgs.scrollTop=msgs.scrollHeight;
  // Typing indicator
  const typId='ai-typing-'+Date.now();
  msgs.innerHTML+=`<div class="ai-msg bot" id="${typId}"><div class="ai-bubble" style="color:var(--g400);">⏳ Hledám v manuálech...</div></div>`;
  msgs.scrollTop=msgs.scrollHeight;
  setTimeout(()=>{
    const resp=aiGetResponse(txt);
    const typEl=document.getElementById(typId);
    if(typEl)typEl.querySelector('.ai-bubble').innerHTML=resp.replace(/\n/g,'<br>');
    msgs.scrollTop=msgs.scrollHeight;
  },700);
}

// ===== MIKROFON / SPEECH RECOGNITION =====
let aiMicActive=false;
let aiRecognition=null;
function aiToggleMic(){
  const btn=document.getElementById('ai-mic-btn');
  const status=document.getElementById('ai-mic-status');
  if(aiMicActive){
    // stop
    if(aiRecognition)aiRecognition.stop();
    aiMicActive=false;
    if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
    if(status)status.style.display='none';
    return;
  }
  // Request mic permission
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){
    showT('❌',_t('sos').voiceInput||'Hlasový vstup',_t('sos').browserNoSpeech||'Váš prohlížeč nepodporuje rozpoznávání řeči');
    return;
  }

  function _startRecognition(){
    aiRecognition=new SR();
    aiRecognition.lang='cs-CZ';
    aiRecognition.continuous=false;
    aiRecognition.interimResults=false;
    aiRecognition.onstart=()=>{
      aiMicActive=true;
      if(btn){btn.style.background='#fee2e2';btn.style.borderColor='var(--red)';btn.textContent='⏹️';}
      if(status)status.style.display='block';
    };
    aiRecognition.onresult=(e)=>{
      const transcript=e.results[0][0].transcript;
      const inp=document.getElementById('ai-chat-inp');
      if(inp)inp.value=transcript;
      showT('🎤',_t('sos').recognized||'Rozpoznáno',transcript.substring(0,40));
    };
    aiRecognition.onend=()=>{
      aiMicActive=false;
      if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
      if(status)status.style.display='none';
      setTimeout(()=>aiSend(),300);
    };
    aiRecognition.onerror=(e)=>{
      aiMicActive=false;
      if(btn){btn.style.background='var(--g100)';btn.style.borderColor='var(--g200)';btn.textContent='🎤';}
      if(status)status.style.display='none';
      if(e.error==='not-allowed')showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micDenied||'Přístup k mikrofonu odepřen');
      else if(e.error==='network')showT('⚠️',_t('sos').voiceInput||'Hlasový vstup','Chyba sítě – zkuste znovu');
      else showT('⚠️',_t('sos').voiceInput||'Hlasový vstup',_t('sos').soundFailed||'Rozpoznávání selhalo – zkuste znovu');
    };
    aiRecognition.start();
  }

  // Try getUserMedia first for permission, fallback to direct start
  if(navigator.mediaDevices && navigator.mediaDevices.getUserMedia){
    navigator.mediaDevices.getUserMedia({audio:true}).then(function(stream){
      // Stop the stream immediately, we just needed the permission
      stream.getTracks().forEach(function(t){t.stop();});
      _startRecognition();
    }).catch(function(){
      // On some devices getUserMedia fails but SpeechRecognition works
      try { _startRecognition(); }
      catch(e){ showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micAllow||'Povolte mikrofon v nastavení'); }
    });
  } else {
    // No getUserMedia (HTTP or old browser) – try starting recognition directly
    try { _startRecognition(); }
    catch(e){ showT('❌',_t('sos').mic||'Mikrofon',_t('sos').micAllow||'Povolte mikrofon v nastavení'); }
  }
}

