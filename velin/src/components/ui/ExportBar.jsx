import Button from './Button'
import { useLang } from '../../i18n/LanguageProvider'

export default function ExportBar() {
  const { t } = useLang()
  return (
    <div className="flex gap-2 mt-4 pt-3" style={{ borderTop: '1px solid #d4e8e0' }}>
      <span
        className="text-sm font-bold mr-1"
        style={{ color: '#1a2e22', lineHeight: '30px' }}
      >
        {t('common.export').toUpperCase()}:
      </span>
      {['PDF', 'XLSX', 'CSV', 'XML', 'JSON'].map((f) => (
        <Button key={f} style={{ padding: '4px 14px', fontSize: 13 }}>
          {f}
        </Button>
      ))}
    </div>
  )
}
