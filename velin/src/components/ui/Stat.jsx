import Card from './Card'

export default function Stat({ icon, label, value, sub, color = '#1a8a18' }) {
  return (
    <Card style={{ flex: 1, minWidth: 160, position: 'relative', overflow: 'hidden' }}>
      <div
        className="absolute -top-2.5 -right-2.5 text-5xl opacity-[0.06]"
      >
        {icon}
      </div>
      <div
        className="text-[10px] font-extrabold uppercase tracking-widest mb-1.5"
        style={{ color: '#8aab99' }}
      >
        {label}
      </div>
      <div
        className="text-2xl font-black tracking-tight"
        style={{ color }}
      >
        {value}
      </div>
      {sub && (
        <div className="text-[11px] font-medium mt-1" style={{ color: '#8aab99' }}>
          {sub}
        </div>
      )}
    </Card>
  )
}
