// ===== MotoGo24 Web — Supabase Client Init =====
// Používá Supabase CDN SDK, inicializuje window.supabase klienta.

(function(){
  var cfg = window.MOTOGO_CONFIG || {};
  if(!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY){
    console.error('[MG-WEB] Chybí SUPABASE_URL/ANON_KEY');
    window.sb = null; return;
  }
  var sdk = window.supabase;
  if(!sdk || typeof sdk.createClient !== 'function'){
    console.error('[MG-WEB] Supabase SDK nenalezen');
    window.sb = null; return;
  }
  try {
    window.sb = sdk.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  } catch(e){
    console.error('[MG-WEB] Supabase init error:', e);
    window.sb = null;
  }
})();
