import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { debugAction } from '../../lib/debugLog'
import Card from '../../components/ui/Card'

// Známé feature flags — co reálně řídí + co znamená zapnuto/vypnuto.
// Klíč = `feature_flags.key` v DB. Pokud flag v DB tento metadata nemá,
// zobrazí se jako „neznámý" (řídí ho vývojář v kódu).
const KNOWN_FLAGS = {
  inventory_v2: {
    title: 'Sklad výbavy v2 (živá dostupnost)',
    controls: 'Rezervační formulář na webu (motogo24.cz), krok 5 — výběr výbavy.',
    on: 'Web při výběru helmy/bundy/bot/rukavic kontroluje SKUTEČNÝ počet kusů na pobočce a souběžné rezervace (RPC get_accessory_availability) — vyprodané velikosti zešednou.',
    off: 'Web nabízí všechny velikosti bez kontroly skladu (jako dřív). Bezpečné vypnout, pokud sklad ještě není naplněný.',
  },
  reservation_upsell: {
    title: 'Doprodej v rezervaci (doplňky z e-shopu)',
    controls: 'Rezervační flow — web (PC i mobil) i mobilní aplikace: sekce „Doplňky na cestu" / doporučené produkty z e-shopu.',
    on: 'Zákazníkovi se v rezervaci nabízí doprodej zboží z e-shopu (přidá k objednávce, samostatná faktura).',
    off: 'Doprodej je skrytý — rezervace nenabízí žádné e-shopové doplňky. Doporučený stav, dokud doprodej nedoplníme.',
  },
  loyalty_leaderboard: {
    title: 'Žebříček jezdců v aplikaci',
    controls: 'Mobilní aplikace — stránka Věrnostní ranky, sekce „Žebříček jezdců".',
    on: 'Zákazník vidí anonymní měsíční žebříček (přezdívka nebo křestní jméno s číslem, postup ranků, km bez nehody) a může se z něj odhlásit.',
    off: 'Žebříček se v appce NEZOBRAZUJE. Backend data dál sbírá a vyhodnocuje (ranky, km z protokolů, měsíční vítěz) — jen se neukazují. Doporučený stav.',
  },
  self_service_delivery: {
    title: 'Přistavení a vyzvednutí na adrese u samoobslužných poboček',
    controls: 'Mobilní aplikace (rezervační formulář + úprava rezervace), web motogo24.cz (rezervace /rezervace + úprava /upravit-rezervaci) a DB trigger nad rezervacemi — u motorek z pobočky typu „samoobslužná". Řádek flagu vzniká SQL migrací (nezakládá se ručně).',
    on: 'Zákazník si u motorek ze samoobslužné pobočky může zvolit přistavení na adresu i odvoz (vyzvednutí) z adresy — stejně jako u obslužné pobočky.',
    off: 'Výchozí stav (rozhodnutí majitele 2026-09-28): motorky ze samoobslužné pobočky se přebírají i vracejí JEN na pobočce. Volby přistavení/odvozu jsou v appce i na webu vidět, ale zabalené a zablokované s vysvětlením; DB trigger takovou rezervaci odmítne.',
  },
  eshop_visible: {
    title: 'E-shop v menu (web + aplikace)',
    controls: 'Hlavní menu a patička webu motogo24.cz + menu v Profilu mobilní aplikace. Řádek flagu vzniká SQL migrací.',
    on: 'Položka „E-shop" je v menu webu i appky vidět (vedle „Pobočky").',
    off: 'Výchozí stav (zadání majitele 2026-10-01): e-shop se v menu NEZOBRAZUJE — místo něj je záložka „Pobočky". Stránky e-shopu dál fungují na přímý odkaz. Web změnu ukáže hned (Velín vyčistí cache webu), appka po znovuotevření menu.',
  },
  debug_mode: {
    title: 'Debug režim Velínu',
    controls: 'Tento administrační panel (Velín).',
    on: 'Zapne diagnostiku — debug panel, podrobné logování akcí do debug_log. Pro vývoj a hledání chyb.',
    off: 'Normální provoz bez diagnostiky. Doporučený stav pro běžné používání.',
  },
}

// Web (PHP) drží flagy i hotové stránky v cache (až 30 min) — po přepnutí ji
// vyčistíme stejně jako Texty webu (`/api/cms-cache-purge`), ať se např. menu
// s e-shopem změní hned. Fire-and-forget, selhání není kritické.
const WEB_BASE_URL = (import.meta?.env?.VITE_WEB_BASE_URL || 'https://www.motogo24.cz').replace(/\/$/, '')
async function purgeWebCache() {
  try {
    const { data } = await supabase.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
    const token = data?.value ? String(data.value) : ''
    if (!token) return
    fetch(WEB_BASE_URL + '/api/cms-cache-purge', {
      method: 'POST', headers: { 'X-CMS-Admin-Token': token }, keepalive: true,
    }).catch(() => {})
  } catch (_) { /* ignore */ }
}

export default function FeatureFlagsTab() {
  const [flags, setFlags] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('feature_flags')
      .select('*')
      .order('key')
    if (err) setError(err.message)
    else setFlags(data || [])
    setLoading(false)
  }

  async function toggle(flag) {
    const newEnabled = !flag.enabled
    const result = await debugAction('featureFlag.toggle', 'FeatureFlagsTab', () =>
      supabase.from('feature_flags').update({ enabled: newEnabled }).eq('id', flag.id)
    , { flag_id: flag.id, flag_name: flag.name, enabled: newEnabled })
    if (result?.error) {
      setError(result.error.message)
      return
    }
    setFlags(f => f.map(fl => fl.id === flag.id ? { ...fl, enabled: newEnabled } : fl))
    purgeWebCache()
    // Audit log — admin_audit_log má sloupce action/entity_type/entity_id/old_data/new_data
    // (NEMÁ `details` — dřívější zápis sem tiše selhával). Opraveno na reálné schéma.
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: 'feature_flag_toggled',
        entity_type: 'feature_flags',
        entity_id: flag.id,
        old_data: { enabled: flag.enabled },
        new_data: { key: flag.key, name: flag.name, enabled: newEnabled },
      })
    } catch {}
  }

  if (loading) return <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>

  if (error) return <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>

  return (
    <div className="space-y-3">
      {/* Vysvětlení co feature flags jsou */}
      <div style={{ background: '#f1faf7', borderLeft: '4px solid #74FB71', borderRadius: 8, padding: 14 }}>
        <div className="font-extrabold text-sm" style={{ color: '#0f1a14', marginBottom: 4 }}>Co jsou Feature flags (přepínače funkcí)</div>
        <div className="text-sm" style={{ color: '#1a2e22', lineHeight: 1.55 }}>
          Jsou to <strong>vypínače celých funkcí</strong> webu a Velínu — ne texty. Zapnutím/vypnutím přepneš chování
          aplikace bez zásahu do kódu. <strong>Většinou je nemusíš měnit</strong> — slouží vývojáři pro postupné
          zavádění funkcí. U každého přepínače níže je vysvětleno, co přesně řídí a co znamená zapnuto/vypnuto.
        </div>
      </div>

      {flags.length === 0 && <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné feature flags v databázi.</p></Card>}

      {flags.map(f => {
        const meta = KNOWN_FLAGS[f.key]
        return (
          <Card key={f.id}>
            <div className="flex items-start gap-4">
              <div className="flex-1 max-lg:min-w-0 max-lg:[overflow-wrap:anywhere]">
                <div className="flex items-center gap-2 max-lg:flex-wrap">
                  <div className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{meta?.title || f.key || f.name || 'Bez názvu'}</div>
                  <code className="max-lg:[overflow-wrap:anywhere]" style={{ fontSize: 11, background: '#eef5f1', color: '#1a8c1a', padding: '1px 6px', borderRadius: 4 }}>{f.key || f.name}</code>
                  <span style={{ fontSize: 11, fontWeight: 700, color: f.enabled ? '#16a34a' : '#9ca3af' }}>
                    {f.enabled ? '● ZAPNUTO' : '○ VYPNUTO'}
                  </span>
                </div>
                {meta ? (
                  <div className="text-sm mt-2" style={{ color: '#1a2e22', lineHeight: 1.5 }}>
                    <div style={{ marginBottom: 4 }}><strong>Řídí:</strong> {meta.controls}</div>
                    <div style={{ color: f.enabled ? '#166534' : '#6b7a72' }}>
                      <strong>{f.enabled ? 'Teď (zapnuto):' : 'Po zapnutí:'}</strong> {meta.on}
                    </div>
                    <div style={{ color: !f.enabled ? '#166534' : '#6b7a72', marginTop: 2 }}>
                      <strong>{!f.enabled ? 'Teď (vypnuto):' : 'Po vypnutí:'}</strong> {meta.off}
                    </div>
                  </div>
                ) : (
                  <div className="text-sm mt-1" style={{ color: '#6b7a72' }}>
                    {f.description || 'Tento přepínač řídí vývojář v kódu — bez popisu. Neměň ho, pokud nevíš co dělá.'}
                  </div>
                )}
              </div>
              <ToggleSwitch enabled={f.enabled} onToggle={() => toggle(f)} />
            </div>
          </Card>
        )
      })}
    </div>
  )
}

function ToggleSwitch({ enabled, onToggle }) {
  return (
    <button
      onClick={onToggle}
      className="relative cursor-pointer transition-colors shrink-0 max-lg:before:content-[''] max-lg:before:absolute max-lg:before:-inset-2"
      style={{
        width: 48,
        height: 26,
        borderRadius: 13,
        background: enabled ? '#74FB71' : '#d4e8e0',
        border: 'none',
        padding: 0,
      }}
    >
      <span
        className="absolute top-1 transition-all rounded-full"
        style={{
          width: 18,
          height: 18,
          background: '#fff',
          left: enabled ? 26 : 4,
          boxShadow: '0 2px 4px rgba(0,0,0,.15)',
        }}
      />
    </button>
  )
}
