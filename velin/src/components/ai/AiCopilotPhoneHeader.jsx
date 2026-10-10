// AI Copilot — hlavička chatu jen pro telefon (desktop/tablet ji nepoužívá).
// compact = telefon na šířku (nízký displej): jeden řádek s menším odsazením,
// ať zbude víc výšky pro zprávy (49 px místo 65 px).
export default function AiCopilotPhoneHeader({ compact, enabledCount, onBack }) {
  return (
    <div className={compact ? 'px-3 py-1 flex items-center gap-3' : 'p-3 flex items-center gap-3'} style={{ borderBottom: '1px solid #d4e8e0' }}>
      <button onClick={onBack} className="shrink-0 rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '0 12px', minHeight: 40, background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>‹ Konverzace</button>
      {compact ? (
        <div className="min-w-0 truncate text-sm" style={{ color: '#1a2e22' }}>
          <span className="font-extrabold" style={{ color: '#0f1a14' }}>AI Copilot</span> — {enabledCount} agentů aktivních
        </div>
      ) : (
        <div className="min-w-0 leading-tight">
          <div className="text-sm font-extrabold" style={{ color: '#0f1a14' }}>AI Copilot</div>
          <div className="text-sm" style={{ color: '#1a2e22' }}>— {enabledCount} agentů aktivních</div>
        </div>
      )}
    </div>
  )
}
