/**
 * MotoGo24 — Edge Function: resolve-mapy-route
 *
 * Rozbalí zkrácený sdílecí odkaz Mapy.com (mapy.com/s/…) na plnou URL,
 * vytáhne parametr `rc` a dekóduje body trasy. Prohlížeč (Velín) to sám
 * nezvládne — sdílecí stránka neposílá CORS hlavičky a redirect Location
 * je u cross-origin fetche neviditelný. Plnou URL s `rc` si Velín dekóduje
 * sám (lib/mapyRoute.js), sem chodí jen `/s/…` zkratky / iframe.
 *
 * POST /functions/v1/resolve-mapy-route
 * Body: { url: string }   // mapy.com/s/… nebo plná URL
 * Auth: Bearer JWT přihlášeného admina (ověřeno přes RPC is_admin).
 * Odpověď: { success, url, rc, waypoints:[{lat,lng}] } | { success:false, error }
 *
 * Body trasy = Mapy.cz `rc` delta-kódování (custom base64, čteno odzadu,
 * přesnost 2^28). Algoritmus ověřen proti reálnému odkazu.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })

// ── Dekodér Mapy.cz `rc` (port z velin/src/lib/mapyRoute.js) ──
const ALPHABET = '0ABCD2EFGH4IJKLMN6OPQRST8UVWXYZ-1abcd3efgh5ijklmn7opqrst9uvwxyz.'

function parseNumber(arr: string[], count: number): number {
  let result = 0
  let i = count
  while (i) {
    if (!arr.length) throw new Error('Neplatná data trasy (rc)')
    const ch = arr.pop() as string
    const index = ALPHABET.indexOf(ch)
    if (index === -1) continue
    result = (result << 6) + index
    i--
  }
  return result
}

function decodeRouteCoords(rc: string): Array<{ lat: number; lng: number }> {
  if (!rc) return []
  const FIVE = (1 + 2) << 4
  const THREE = 1 << 5
  const results: Array<{ lat: number; lng: number }> = []
  const coords = [0, 0]
  let ci = 0
  const arr = String(rc).trim().split('').reverse()
  while (arr.length) {
    let num = parseNumber(arr, 1)
    if ((num & FIVE) === FIVE) {
      num -= FIVE
      num = ((num & 15) << 24) + parseNumber(arr, 4)
      coords[ci] = num
    } else if ((num & THREE) === THREE) {
      num = ((num & 15) << 12) + parseNumber(arr, 2)
      num -= 1 << 15
      coords[ci] += num
    } else {
      num = ((num & 31) << 6) + parseNumber(arr, 1)
      num -= 1 << 10
      coords[ci] += num
    }
    if (ci) {
      const lng = (coords[0] * 360) / (1 << 28) - 180
      const lat = (coords[1] * 180) / (1 << 28) - 90
      results.push({ lat: Math.round(lat * 1e6) / 1e6, lng: Math.round(lng * 1e6) / 1e6 })
    }
    ci = (ci + 1) % 2
  }
  return results
}

function rcFromUrl(url: string): string | null {
  try {
    return new URL(url).searchParams.get('rc')
  } catch {
    return null
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ success: false, error: 'Method not allowed' }, 405)

  try {
    // ── Auth: jen přihlášený admin ──
    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader) return json({ success: false, error: 'Chybí autorizace' }, 401)
    const supa = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user } } = await supa.auth.getUser()
    if (!user) return json({ success: false, error: 'Neautorizováno' }, 401)
    const { data: isAdmin } = await supa.rpc('is_admin')
    if (!isAdmin) return json({ success: false, error: 'Přístup jen pro administrátory' }, 403)

    const { url } = await req.json().catch(() => ({}))
    if (!url || typeof url !== 'string') return json({ success: false, error: 'Chybí odkaz (url)' }, 400)

    // Plná URL už rc obsahuje — dekódovat rovnou (bez fetche).
    let finalUrl = url
    let rc = rcFromUrl(url)

    if (!rc) {
      // Zkrácený odkaz → následuj redirect (browser UA, ať mapy neodmítnou).
      const res = await fetch(url, {
        redirect: 'follow',
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Accept-Language': 'cs,en;q=0.8',
          'Accept': 'text/html,application/xhtml+xml',
        },
      })
      finalUrl = res.url || url
      rc = rcFromUrl(finalUrl)
      // Fallback: někdy je rc až v těle stránky (canonical/redirect meta).
      if (!rc) {
        const body = await res.text().catch(() => '')
        const m = body.match(/[?&]rc=([^&"'\\\s]+)/)
        if (m) rc = decodeURIComponent(m[1])
      }
    }

    if (!rc) {
      return json({
        success: false,
        error: 'V odkazu se nepodařilo najít body trasy (rc). Otevři odkaz v Mapy.com, zkopíruj plnou URL z adresního řádku a vlož ji sem.',
      }, 422)
    }

    const waypoints = decodeRouteCoords(rc)
    if (!waypoints.length) {
      return json({ success: false, error: 'Body trasy se nepodařilo dekódovat.' }, 422)
    }

    return json({ success: true, url: finalUrl, rc, waypoints })
  } catch (e) {
    return json({ success: false, error: (e as Error).message || 'Chyba serveru' }, 500)
  }
})
