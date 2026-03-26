// ===== MotoGo24 Web — Supabase Client Init =====
// SDK je bundlovaný lokálně v js/supabase-sdk.js (stejný jako v mobilní appce)
// SDK nastaví window.supabase = { createClient: ... }
// My uložíme klienta do window.sb

(function(){
  var cfg = window.MOTOGO_CONFIG || {};
  if(!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY){
    console.error('[MG-WEB] Chybí SUPABASE_URL/ANON_KEY');
    window.sb = null; return;
  }
  // SDK nastaví window.supabase jako namespace s createClient
  var sdk = window.supabase;
  if(!sdk || typeof sdk.createClient !== 'function'){
    console.error('[MG-WEB] Supabase SDK nenalezen. window.supabase =', typeof window.supabase);
    window.sb = null; return;
  }
  try {
    window.sb = sdk.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
    console.log('[MG-WEB] Supabase klient inicializován OK');
  } catch(e){
    console.error('[MG-WEB] Supabase init error:', e);
    window.sb = null;
  }
})();
