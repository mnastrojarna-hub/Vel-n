// MotoGo24 — Velín → invalidace server-side cache veřejného webu (motogo24.cz)
//
// Web má dvě cache vrstvy (supabase.php file-cache 30 min + page_cache.php
// 10 min). Po změně dat, která ovlivňují veřejný katalog (stav motorky,
// pobočka, cena, kategorie…), je nutné cache zneplatnit, jinak návštěvník
// uvidí starý stav až do vypršení TTL. CMS „Texty webu" tohle už dělá po
// uložení — tento helper sdílí stejný endpoint pro ostatní místa Velína.

import { supabase } from './supabase'

export const WEB_BASE_URL = (import.meta?.env?.VITE_WEB_BASE_URL || 'https://www.motogo24.cz').replace(/\/$/, '')

let _tokenPromise = null
function getAdminToken() {
  if (!_tokenPromise) {
    _tokenPromise = supabase.from('app_settings').select('value').eq('key', 'cms_admin_token').maybeSingle()
      .then(({ data }) => {
        const v = data?.value
        return v ? String(typeof v === 'string' ? v : v) : ''
      })
      .catch(() => '')
  }
  return _tokenPromise
}

// Fire-and-forget: nečekáme na response, selhání je netragické (cache stejně
// vyprší sama). Bez `cms_admin_token` v app_settings se purge přeskočí.
export async function purgeWebCache() {
  try {
    const token = await getAdminToken()
    if (!token) return
    fetch(WEB_BASE_URL + '/api/cms-cache-purge', {
      method: 'POST',
      headers: { 'X-CMS-Admin-Token': token },
      keepalive: true,
    }).catch(() => {})
  } catch (_) { /* ignore */ }
}

// Bumpne verzi znalostní báze veřejného AI agenta (`app_settings.ai_kb_version`).
// Edge fn `ai-public-agent` drží FAQ + smluvní dokumenty + podmínky v 5min
// in-memory cache (`kbCache`), kterou nelze externě purgnout (běží v Deno
// isolatu). Místo čekání na TTL agent při každé zprávě porovná tuto verzi a
// když se změnila, načte znalostní bázi znovu hned. Volá se po každé změně
// obsahu, který agent čte (FAQ, smluvní texty, podmínky půjčovny).
export async function bumpKbVersion() {
  try {
    await supabase.from('app_settings').upsert(
      { key: 'ai_kb_version', value: Date.now() },
      { onConflict: 'key' }
    )
  } catch (_) { /* ignore — agent se i tak srovná do 5 min přes TTL */ }
}

// Zneplatní obě cache najednou: server-side cache veřejného webu (page_cache +
// data cache) i znalostní bázi AI agenta. Použij po změně obsahu, který čte
// jak web, tak agent (FAQ, smluvní dokumenty, podmínky).
export async function purgeWebAndAgentCache() {
  await Promise.all([purgeWebCache(), bumpKbVersion()])
}
