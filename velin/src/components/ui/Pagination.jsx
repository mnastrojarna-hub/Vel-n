export default function Pagination({ page, totalPages, onPageChange }) {
  if (totalPages <= 1) return null

  const pages = []
  for (let i = 1; i <= totalPages; i++) {
    if (i === 1 || i === totalPages || (i >= page - 1 && i <= page + 1)) {
      pages.push(i)
    } else if (pages[pages.length - 1] !== '...') {
      pages.push('...')
    }
  }

  return (
    <div className="flex items-center justify-center gap-1 mt-4">
      <button
        onClick={() => onPageChange(page - 1)}
        disabled={page <= 1}
        className="rounded-btn text-xs font-extrabold cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
        style={{ padding: '6px 14px', background: '#f1faf7', color: '#4a6357', border: 'none' }}
      >
        ←
      </button>
      {pages.map((p, i) =>
        p === '...' ? (
          <span key={`dots-${i}`} style={{ padding: '6px 8px', color: '#8aab99', fontSize: 12 }}>
            …
          </span>
        ) : (
          <button
            key={p}
            onClick={() => onPageChange(p)}
            className="rounded-btn text-xs font-extrabold cursor-pointer"
            style={{
              padding: '6px 14px',
              background: p === page ? '#74FB71' : '#f1faf7',
              color: p === page ? '#1a2e22' : '#4a6357',
              border: 'none',
              boxShadow: p === page ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
            }}
          >
            {p}
          </button>
        )
      )}
      <button
        onClick={() => onPageChange(page + 1)}
        disabled={page >= totalPages}
        className="rounded-btn text-xs font-extrabold cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
        style={{ padding: '6px 14px', background: '#f1faf7', color: '#4a6357', border: 'none' }}
      >
        →
      </button>
    </div>
  )
}
