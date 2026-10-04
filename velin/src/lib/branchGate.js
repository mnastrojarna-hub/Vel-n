import { useState, useEffect } from 'react'
import { supabase } from './supabase'

// ─── Vjezdová brána pobočky (2026-10-04, migrace 20261004_vn_gate_access.sql) ──────────────
// Tabulka `branch_gate_access` = kód SCHRÁNKY s klíčem od visacího zámku vjezdové brány (Velké Němčice:
// horní schránka na pravém sloupku vrat). RLS jen admin — Velín ji čte/edituje přímo. Zákazník dostává
// kód jako 1. kód (brána → šatna → motorka) jen v osobních kanálech (appka, e-mail, SMS/WA, zprávy).
// BEZPEČNOST: kód nikdy do veřejných textů (poznámky pobočky, FAQ, web), do logů ani do tohoto bundle
// (Velín je veřejně stažitelný JS) — žádné natvrdo zapsané číslice, vždy jen z DB.

export const GATE_CODE_RE = /^[0-9]{3,8}$/
// Stejný popisek jako v in-app zprávě z DB (`_door_codes_msg_lines`)
export const GATE_MSG_LABEL = 'Kód schránky s klíčem od brány'

/** Aktivní kód brány pobočky, nebo null (pobočka bránu nemá / kód vypnutý / chyba načtení). */
export async function fetchActiveGateCode(branchId) {
  if (!branchId) return null
  const { data, error } = await supabase.from('branch_gate_access')
    .select('lockbox_code').eq('branch_id', branchId).eq('is_active', true).maybeSingle()
  if (error) { console.warn('[branchGate] načtení kódu brány selhalo:', error.message); return null }
  return data?.lockbox_code || null
}

/** Hook: aktivní kód brány pobočky (null = bez brány / ještě nenačteno). */
export function useBranchGateCode(branchId) {
  const [code, setCode] = useState(null)
  useEffect(() => {
    let alive = true
    setCode(null)
    fetchActiveGateCode(branchId).then(c => { if (alive) setCode(c) }, () => {})
    return () => { alive = false }
  }, [branchId])
  return code
}

/**
 * Řádek kódu daného typu (motorcycle / accessories) z `branch_door_codes` rezervace: přednost má AKTIVNÍ,
 * pak NEJNOVĚJŠÍ. Po změně motorky / přesunu pobočky regen deaktivuje staré řádky a založí nové — první
 * nalezený řádek tak mohl být starý neaktivní kód.
 */
export function pickDoorCode(codes, type) {
  return (codes || []).filter(c => c.code_type === type)
    .sort((a, b) => (Number(b.is_active === true) - Number(a.is_active === true))
      || String(b.created_at || '').localeCompare(String(a.created_at || '')))[0]
}
