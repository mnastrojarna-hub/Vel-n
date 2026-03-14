// ===== MotoGo24 – Supabase Client (Production v5.0.0) =====
// SDK je bundlovaný lokálně v src/services/supabase-sdk.js
// Žádný mock fallback — pokud není Supabase, appka zobrazí offline hlášku.

// DŮLEŽITÉ: Nepoužívat "var supabase = null" na global scope!
// supabase-sdk.js nastaví window.supabase = { createClient: ... }
// a "var supabase = null" by to okamžitě přepsalo na null.

(function() {
    var cfg = window.MOTOGO_CONFIG || {};
    if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
        console.error('[MG] CHYBA: Chybí SUPABASE_URL nebo SUPABASE_ANON_KEY v MOTOGO_CONFIG');
        window.supabase = null;
        return;
    }

    // Uložit referenci na SDK dřív, než ji přepíšeme klientem
    var sdk = window.supabase;
    if (!sdk || typeof sdk.createClient !== 'function') {
        console.error('[MG] CHYBA: Supabase SDK nenalezen — supabase-sdk.js chybí nebo je poškozený');
        console.error('[MG] window.supabase =', typeof window.supabase, window.supabase);
        window.supabase = null;
        return;
    }

    try {
        // Přepsat window.supabase z SDK namespace na klienta
        window.supabase = sdk.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
    } catch(e) {
        console.error('[MG] Supabase init selhal:', e);
        window.supabase = null;
    }
})();

/** Vrací true pokud je Supabase klient připravený. */
function isSupabaseOnline() {
    return window.supabase !== null && window.supabase !== undefined;
}
