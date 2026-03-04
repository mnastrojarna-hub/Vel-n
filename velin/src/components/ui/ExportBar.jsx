import Button from './Button'

export default function ExportBar() {
  return (
    <div className="flex gap-2 mt-4 pt-3" style={{ borderTop: '1px solid #d4e8e0' }}>
      <span
        className="text-[11px] font-bold mr-1"
        style={{ color: '#8aab99', lineHeight: '30px' }}
      >
        EXPORT:
      </span>
      {['PDF', 'XLSX', 'CSV', 'XML', 'JSON'].map((f) => (
        <Button key={f} style={{ padding: '4px 14px', fontSize: 10 }}>
          {f}
        </Button>
      ))}
    </div>
  )
}
