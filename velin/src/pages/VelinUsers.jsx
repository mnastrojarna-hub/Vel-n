import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { Table, TRow, TH, TD } from '../components/ui/Table'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import VelinUserModal, { ROLE_LABELS, callAdminUsers } from './VelinUserModal'
import { describeSections } from '../lib/velinSections'

/**
 * Uživatelé Velína — jen superadmin. Založení účtu (e-mail + heslo), výběr
 * sekcí hlavního menu, které účet vidí (admin_users.permissions.sections),
 * změna hesla, deaktivace a odebrání přístupu. Zápisy jdou přes edge funkci
 * `admin-users` (service role: auth.admin.createUser + admin_users), čtení
 * seznamu přímo (RLS admin_users_read = is_admin()).
 */
export default function VelinUsers({ admin }) {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showAdd, setShowAdd] = useState(false)
  const [editUser, setEditUser] = useState(null)
  const [confirm, setConfirm] = useState(null) // { kind: 'remove'|'toggle', user }
  const [busy, setBusy] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true); setError(null)
    try {
      const { data, error: e } = await supabase
        .from('admin_users')
        .select('id, email, name, role, phone, active, permissions, last_login_at, created_at')
        .order('created_at', { ascending: true })
      if (e) throw e
      setUsers(data || [])
    } catch (e) { setError(e.message) } finally { setLoading(false) }
  }

  async function runConfirm() {
    if (!confirm) return
    setBusy(true); setError(null)
    try {
      if (confirm.kind === 'remove') {
        await callAdminUsers({ action: 'delete', user_id: confirm.user.id })
      } else {
        await callAdminUsers({ action: 'update', user_id: confirm.user.id, active: !confirm.user.active })
      }
      setConfirm(null)
      await load()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }

  const isSelf = (u) => u.id === admin?.id
  const fmtDate = (d) => d ? new Date(d).toLocaleString('cs-CZ', { dateStyle: 'short', timeStyle: 'short' }) : '—'

  return (
    <div>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <Button green onClick={() => setShowAdd(true)}>+ Nový uživatel</Button>
        <span className="text-sm font-medium" style={{ color: '#1a2e22' }}>
          Účet se přihlašuje e-mailem a heslem jako vy; vidí jen zaškrtnuté sekce menu.
          Zapomenuté heslo si obnoví sám na přihlašovací stránce („Zapomenuté heslo?“ → kód e-mailem).
        </span>
      </div>
      {error && <div className="mb-3 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
      {loading ? (
        <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
      ) : (
        // 7 sloupců → na telefonu i tabletu karty; akce přes celou šířku karty (desktop beze změny)
        <Table stack="tablet" className="mg-stack-2col">
          <thead>
            <TRow header>
              <TH>Jméno</TH><TH>E-mail</TH><TH>Role</TH><TH>Vidí sekce</TH>
              <TH>Poslední přihlášení</TH><TH>Stav</TH><TH>Akce</TH>
            </TRow>
          </thead>
          <tbody>
            {users.map(u => (
              <TRow key={u.id}>
                <TD bold>{u.name || '—'}{isSelf(u) && <span className="ml-2 text-xs font-bold" style={{ color: '#3dba3a' }}>(vy)</span>}</TD>
                <TD>{u.email}</TD>
                <TD><Badge label={ROLE_LABELS[u.role] || u.role}
                  color={u.role === 'superadmin' ? '#1a8a18' : '#2563eb'}
                  bg={u.role === 'superadmin' ? '#dcfce7' : '#dbeafe'} /></TD>
                <TD>{describeSections(u)}</TD>
                <TD>{fmtDate(u.last_login_at)}</TD>
                <TD><span className="text-sm font-bold" style={{ color: u.active ? '#1a8a18' : '#dc2626' }}>
                  {u.active ? 'Aktivní' : 'Neaktivní'}</span></TD>
                <TD className="mg-stack-full">
                  <div className="flex gap-3 flex-wrap max-lg:gap-1 max-lg:-mx-2">
                    <button onClick={() => setEditUser(u)} className="text-sm font-bold cursor-pointer max-lg:py-2 max-lg:px-2"
                      style={{ color: '#2563eb', background: 'none', border: 'none' }}>Upravit</button>
                    {!isSelf(u) && (
                      <>
                        <button onClick={() => setConfirm({ kind: 'toggle', user: u })} className="text-sm font-bold cursor-pointer max-lg:py-2 max-lg:px-2"
                          style={{ color: '#b45309', background: 'none', border: 'none' }}>
                          {u.active ? 'Deaktivovat' : 'Aktivovat'}
                        </button>
                        <button onClick={() => setConfirm({ kind: 'remove', user: u })} className="text-sm font-bold cursor-pointer max-lg:py-2 max-lg:px-2"
                          style={{ color: '#dc2626', background: 'none', border: 'none' }}>Odebrat přístup</button>
                      </>
                    )}
                  </div>
                </TD>
              </TRow>
            ))}
            {users.length === 0 && <TRow><TD className="mg-stack-full">Žádní uživatelé</TD></TRow>}
          </tbody>
        </Table>
      )}

      {showAdd && <VelinUserModal admin={admin} onClose={() => setShowAdd(false)} onSaved={() => { setShowAdd(false); load() }} />}
      {editUser && <VelinUserModal admin={admin} user={editUser} onClose={() => setEditUser(null)} onSaved={() => { setEditUser(null); load() }} />}

      <ConfirmDialog
        open={!!confirm}
        danger={confirm?.kind === 'remove'}
        title={confirm?.kind === 'remove' ? 'Odebrat přístup do Velína' : (confirm?.user?.active ? 'Deaktivovat účet' : 'Aktivovat účet')}
        message={confirm?.kind === 'remove'
          ? `${confirm.user.name || confirm.user.email} se už do Velína nepřihlásí. Přihlašovací účet (e-mail) zůstane zachován — přístup lze později znovu založit.`
          : confirm?.user?.active
            ? `${confirm.user.name || confirm.user.email} se do Velína nepřihlásí, dokud účet znovu neaktivujete.`
            : `${confirm?.user?.name || confirm?.user?.email} se bude moci znovu přihlásit.`}
        onConfirm={busy ? undefined : runConfirm}
        onCancel={() => setConfirm(null)}
      />
    </div>
  )
}
