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
        className="text-sm font-extrabold uppercase tracking-widest mb-1.5"
        style={{ color: '#1a2e22' }}
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
        <div className="text-sm font-medium mt-1" style={{ color: '#1a2e22' }}>
          {sub}
        </div>
      )}
    </Card>
  )
}
