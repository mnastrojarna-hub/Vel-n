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
