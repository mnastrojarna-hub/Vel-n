import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import BlogWizard from './BlogWizard'

export default function BlogSection() {
  const [articles, setArticles] = useState([])
  const [loading, setLoading] = useState(true)
  const [showWizard, setShowWizard] = useState(false)
  const [editing, setEditing] = useState(null)

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    const { data } = await supabase.from('cms_pages').select('*').order('created_at', { ascending: false })
    setArticles(data || [])
    setLoading(false)
  }

  async function togglePublish(article) {
    await supabase.from('cms_pages').update({ published: !article.published, updated_at: new Date().toISOString() }).eq('id', article.id)
    load()
  }

  async function deleteArticle(article) {
    if (!confirm(`Smazat článek "${article.title}"?`)) return
    await supabase.from('cms_pages').delete().eq('id', article.id)
    load()
  }

  return (
    <div>
      {/* Header s popisem */}
      <div className="mb-4">
        <div className="flex items-center gap-3">
          <span style={{ fontSize: 24 }}>📰</span>
          <div>
            <h2 className="text-lg font-extrabold" style={{ color: '#0f1a14', margin: 0 }}>Blog & články</h2>
            <div className="text-xs font-mono" style={{ color: '#6b8f7b' }}>motogo24.cz/blog</div>
          </div>
        </div>
        <p className="text-sm mt-2" style={{ color: '#4a6b5a' }}>
          Články se zobrazují na stránce Blog na webu. Návštěvníci je vidí jako karty s náhledem,
          po kliknutí se otevře celý článek. Štítky slouží k filtrování.
        </p>
      </div>

      {/* Tlačítko nový článek */}
      <div className="flex items-center gap-3 mb-4 p-4 rounded-card" style={{ background: '#f1faf7', border: '2px dashed #74FB71' }}>
        <div className="flex-1">
          <div className="text-sm font-extrabold" style={{ color: '#1a2e22' }}>Přidat nový článek na blog</div>
          <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>Průvodce vás provede 4 kroky: název, obsah, obrázky a publikace</div>
        </div>
        <Button green onClick={() => setShowWizard(true)}>+ Nový článek</Button>
      </div>

      {/* Seznam článků */}
      {loading ? (
        <div className="flex justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" />
        </div>
      ) : articles.length === 0 ? (
        <div className="text-center py-8 text-sm" style={{ color: '#9ab3a5' }}>
          Zatím nemáte žádné články. Klikněte na „+ Nový článek" a vytvořte první.
        </div>
      ) : (
        <div className="space-y-2">
          {articles.map(a => (
            <ArticleRow key={a.id} article={a} onToggle={() => togglePublish(a)} onDelete={() => deleteArticle(a)} onEdit={() => setEditing(a)} />
          ))}
        </div>
      )}

      {/* Wizard modal — autosave + edit existujícího článku/konceptu */}
      {(showWizard || editing) && (
        <BlogWizard
          entry={editing}
          onClose={() => { setShowWizard(false); setEditing(null); load() }}
          onSaved={() => { setShowWizard(false); setEditing(null); load() }}
        />
      )}
    </div>
  )
}

function ArticleRow({ article, onToggle, onDelete, onEdit }) {
  const a = article
  const tags = a.tags || []
  return (
    <div className="flex items-center gap-3 p-3 rounded-card" style={{ background: '#fff', border: '1px solid #e2ece7' }}>
      {/* Náhled obrázku */}
      {a.image_url ? (
        <div className="shrink-0 rounded overflow-hidden" style={{ width: 60, height: 40 }}>
          <img src={a.image_url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            onError={e => { e.target.parentElement.style.display = 'none' }} />
        </div>
      ) : (
        <div className="shrink-0 flex items-center justify-center rounded" style={{ width: 60, height: 40, background: '#e2ece7', color: '#9ab3a5', fontSize: 18 }}>📝</div>
      )}

      {/* Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-extrabold text-sm truncate" style={{ color: '#0f1a14' }}>{a.title}</span>
          <span
            className="text-xs font-bold rounded-btn shrink-0"
            style={{
              padding: '1px 8px',
              background: a.published ? '#dcfce7' : '#fef3c7',
              color: a.published ? '#16a34a' : '#b45309',
            }}
          >
            {a.published ? 'Publikováno' : 'Koncept'}
          </span>
        </div>
        <div className="text-xs mt-0.5 truncate" style={{ color: '#6b8f7b' }}>
          /blog/{a.slug}
          {tags.length > 0 && <span> · {tags.join(', ')}</span>}
          {a.updated_at && <span> · {new Date(a.updated_at).toLocaleDateString('cs-CZ')}</span>}
        </div>
      </div>

      {/* Akce */}
      <div className="flex gap-1 shrink-0">
        <SmBtn label="Upravit" onClick={onEdit} />
        <SmBtn label={a.published ? 'Skrýt' : 'Zveřejnit'} onClick={onToggle} />
        <SmBtn label="Smazat" onClick={onDelete} danger />
      </div>
    </div>
  )
}

function SmBtn({ label, onClick, danger }) {
  return (
    <button onClick={onClick} className="rounded-btn text-xs font-bold cursor-pointer"
      style={{
        padding: '4px 10px', border: 'none',
        background: danger ? '#fee2e2' : '#f1faf7',
        color: danger ? '#dc2626' : '#1a2e22',
      }}
    >{label}</button>
  )
}
