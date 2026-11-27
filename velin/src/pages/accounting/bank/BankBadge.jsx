import { useState, useEffect } from 'react'
import { subscribeBankBadge } from './bankBadgeStore'

// Odznak na záložce „Banka“: počet pohybů k vyřešení; „!“ když synchronizace selhává nebo končí platnost tokenu.
// Dokud databázová část neexistuje, nevykreslí nic.
export default function BankBadge() {
  const [b, setB] = useState({ count: 0, alert: false })
  useEffect(() => subscribeBankBadge(setB), [])
  if (!b.count && !b.alert) return null
  return (
    <span className="ml-1.5 inline-flex items-center justify-center rounded-full font-extrabold align-middle"
      title={b.count ? `${b.count} bankovních pohybů k vyřešení` : 'Banka vyžaduje pozornost'}
      style={{ minWidth: 18, height: 18, padding: '0 5px', fontSize: 10, background: '#dc2626', color: '#fff' }}>
      {b.count || '!'}
    </span>
  )
}
