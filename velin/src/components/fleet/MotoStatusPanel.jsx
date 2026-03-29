import Button from '../ui/Button'
import StatusBadge from '../ui/StatusBadge'
import { StatusBtn, UnavailableReasonPicker } from './MotoActionHelpers'

export default function MotoStatusPanel({
  moto, branches, selectedBranch, setSelectedBranch,
  handleMigrate, handleStatusChange, handleCloseServiceAndActivate,
  handleDeactivateSimple, setShowChecklist, setShowDeactReplace,
  reason, setReason, customReason, setCustomReason,
  unavailableUntil, setUnavailableUntil,
  openLogs, busy, success, error, onClose, isSamoobsluzna,
}) {
  const isActive = moto.status === 'active'
  const isMaintenance = moto.status === 'maintenance'
  const isOut = moto.status === 'unavailable'
  const hasOpenLogs = openLogs.length > 0

  return (
    <>
      {success && <div className="mb-4 p-3 rounded-card" style={{ background: '#dcfce7', color: '#1a8a18', fontSize: 13 }}>{success}</div>}
      {error && <div className="mb-4 p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      <div className="flex items-center gap-3 mb-5 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <span className="font-extrabold text-sm" style={{ color: '#0f1a14' }}>{moto.model}</span>
        <span className="font-mono text-sm" style={{ color: '#1a2e22' }}>{moto.spz}</span>
        <StatusBadge status={moto.status} />
        {moto.branches?.name && <span className="text-sm ml-auto" style={{ color: '#1a2e22' }}>Pobočka: <b>{moto.branches.name}</b></span>}
      </div>

      {isActive && hasOpenLogs && (
        <div className="mb-4 p-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fde68a' }}>
          <div className="text-sm font-bold mb-1" style={{ color: '#b45309' }}>
            Motorka je aktivní, ale má {openLogs.length} otevřený servisní záznam
          </div>
          <div className="text-xs mb-2" style={{ color: '#92400e' }}>
            {openLogs.map(l => l.description || l.status).join(', ')}
          </div>
          <button onClick={handleCloseServiceAndActivate} disabled={busy}
            className="rounded-btn text-sm font-bold cursor-pointer"
            style={{ padding: '6px 14px', background: '#dcfce7', color: '#1a8a18', border: 'none' }}>
            {busy ? 'Uzavírám…' : 'Uzavřít servisní záznamy'}
          </button>
        </div>
      )}

      <div className="mb-5">
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Přesunout na pobočku</h3>
        <div className="flex items-center gap-2">
          <select value={selectedBranch} onChange={e => setSelectedBranch(e.target.value)} className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }}>
            <option value="">— Vyberte cílovou pobočku —</option>
            {branches.filter(b => b.id !== moto.branch_id).map(b => <option key={b.id} value={b.id}>{b.name}{!b.active ? ' (neaktivní)' : ''}</option>)}
          </select>
          <Button green onClick={handleMigrate} disabled={!selectedBranch || busy}>{busy ? 'Přesouvám…' : 'Přesunout'}</Button>
        </div>
      </div>
      <hr style={{ border: 'none', borderTop: '1px solid #d4e8e0', margin: '20px 0' }} />

      <div>
        <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Změnit stav motorky</h3>
        <div className="grid grid-cols-2 gap-3">
          {(isOut || moto.status === 'retired') && hasOpenLogs && (
            <StatusBtn color="#1a8a18" bg="#dcfce7" onClick={() => handleStatusChange('maintenance')} disabled={busy}
              title="Vrátit do servisu" desc={`Obnoví ${openLogs.length} servisní záznam(y) — původní checklist zůstane zachován`} />
          )}
          {(isOut || moto.status === 'retired') && !hasOpenLogs && (
            <StatusBtn color="#b45309" bg="#fef3c7" onClick={() => handleStatusChange('maintenance')} disabled={busy}
              title="Vrátit do servisu" desc="Přesunout motorku zpět do servisu" />
          )}
          {!isActive && (
            <StatusBtn color={hasOpenLogs ? '#dc2626' : '#1a8a18'} bg={hasOpenLogs ? '#fee2e2' : '#dcfce7'} onClick={() => handleStatusChange('active')} disabled={busy}
              title="Vrátit do provozu" desc={hasOpenLogs ? `⚠ Uzavře ${openLogs.length} servisní záznam(y) a aktivuje` : 'Motorka bude opět k dispozici'} />
          )}
          {isActive && hasOpenLogs && (
            <StatusBtn color="#1a8a18" bg="#dcfce7" onClick={handleCloseServiceAndActivate} disabled={busy}
              title="Ukončit servis" desc={`Uzavře ${openLogs.length} otevřený servisní záznam(y)`} />
          )}
          {hasOpenLogs ? (
            <StatusBtn color="#2563eb" bg="#dbeafe" onClick={() => setShowChecklist(true)} disabled={busy}
              title="Upravit servisní plán" desc={`Upravit checklist a údaje (${openLogs.length} otevřený záznam)`} />
          ) : !isMaintenance ? (
            <StatusBtn color="#b45309" bg="#fef3c7" onClick={() => setShowChecklist(true)} disabled={busy}
              title="Odeslat do servisu" desc="Otevře checklist závad a údržby" />
          ) : null}
          {!isOut && <StatusBtn color="#7c3aed" bg="#ede9fe" onClick={() => { if (reason) handleStatusChange('unavailable') }} disabled={busy || !reason}
            title="Dočasně vyřadit" desc="Čištění, tankování, přeprava — vyberte důvod níže" />}
          {moto.status !== 'retired' && <StatusBtn color="#1a2e22" bg="#f3f4f6" onClick={() => { if (window.confirm('Opravdu trvale vyřadit?')) handleStatusChange('retired') }} disabled={busy}
            title="Trvale vyřadit" desc="Motorka bude označena jako vyřazena z flotily" />}
          {isSamoobsluzna && moto.branch_id && (
            <StatusBtn color="#7c3aed" bg="#ede9fe" onClick={() => setShowDeactReplace(true)} disabled={busy}
              title="Deaktivovat + nahradit" desc="Vyřadit a přiřadit jinou motorku na pobočku" />
          )}
          {!isSamoobsluzna && moto.branch_id && !isOut && (
            <StatusBtn color="#7c3aed" bg="#ede9fe" onClick={handleDeactivateSimple} disabled={busy}
              title="Deaktivovat" desc="Dočasně vyřadit z provozu" />
          )}
        </div>
        {!isOut && <UnavailableReasonPicker reason={reason} setReason={setReason} customReason={customReason} setCustomReason={setCustomReason} unavailableUntil={unavailableUntil} setUnavailableUntil={setUnavailableUntil} />}
      </div>
      <div className="flex justify-end mt-5"><Button onClick={onClose}>Zavřít</Button></div>
    </>
  )
}
