import { useEffect, useRef, useState, useCallback } from 'react'

/**
 * WYSIWYG editor s lištou — bez externích závislostí.
 * Použití: <RichTextEditor value={html} onChange={setHtml} placeholder="..." minHeight={300} />
 *
 * Lišta: nadpisy, odstavec, font family, velikost, B/I/U/S, barva, zvýraznění,
 * zarovnání, seznamy, odkaz, obrázek, čára, citace, kód, vyčistit, undo/redo, HTML přepínač.
 */
export default function RichTextEditor({
  value = '',
  onChange,
  placeholder = 'Začněte psát…',
  minHeight = 300,
  variables = null, // volitelné: pole {label, value} tlačítek pro vložení proměnné
}) {
  const editorRef = useRef(null)
  const [isHtmlMode, setIsHtmlMode] = useState(false)
  const [htmlDraft, setHtmlDraft] = useState('')
  const [, force] = useState(0)
  const lastValueRef = useRef('')

  // Sync vnější `value` → editor (jen když se opravdu liší od aktuálního obsahu)
  useEffect(() => {
    if (isHtmlMode) return
    const el = editorRef.current
    if (!el) return
    if (value !== lastValueRef.current && value !== el.innerHTML) {
      el.innerHTML = value || ''
      lastValueRef.current = value || ''
    }
  }, [value, isHtmlMode])

  const emit = useCallback(() => {
    const el = editorRef.current
    if (!el) return
    const html = el.innerHTML
    lastValueRef.current = html
    onChange && onChange(html)
    force(x => x + 1) // re-render pro stav tlačítek lišty
  }, [onChange])

  const exec = useCallback((cmd, val = null) => {
    editorRef.current?.focus()
    try {
      document.execCommand(cmd, false, val)
    } catch (_) { /* ignore */ }
    emit()
  }, [emit])

  const insertHtml = useCallback((html) => {
    editorRef.current?.focus()
    try {
      document.execCommand('insertHTML', false, html)
    } catch (_) { /* ignore */ }
    emit()
  }, [emit])

  const setBlock = (tag) => exec('formatBlock', tag)
  const isActive = (cmd) => {
    try { return document.queryCommandState(cmd) } catch (_) { return false }
  }
  const currentBlock = () => {
    try { return (document.queryCommandValue('formatBlock') || '').toLowerCase() } catch (_) { return '' }
  }

  // Vložení odkazu / obrázku přes prompt
  const promptLink = () => {
    const sel = window.getSelection()
    const hasSelection = sel && sel.toString().length > 0
    const url = window.prompt('URL odkazu (např. https://...)')
    if (!url) return
    if (hasSelection) {
      exec('createLink', url)
    } else {
      const text = window.prompt('Text odkazu', url) || url
      insertHtml(`<a href="${escapeAttr(url)}" target="_blank" rel="noopener">${escapeHtml(text)}</a>`)
    }
  }
  const promptImage = () => {
    const url = window.prompt('URL obrázku (např. https://…/image.jpg)')
    if (!url) return
    insertHtml(`<img src="${escapeAttr(url)}" alt="" style="max-width:100%;height:auto;" />`)
  }

  const togglePlain = () => {
    if (!isHtmlMode) {
      setHtmlDraft(editorRef.current?.innerHTML || '')
      setIsHtmlMode(true)
    } else {
      // Při návratu do WYSIWYG vezmeme aktuální draft
      lastValueRef.current = htmlDraft
      onChange && onChange(htmlDraft)
      setIsHtmlMode(false)
    }
  }

  // Klávesové zkratky
  const onKeyDown = (e) => {
    if (!(e.ctrlKey || e.metaKey)) return
    const k = e.key.toLowerCase()
    if (k === 'b') { e.preventDefault(); exec('bold') }
    else if (k === 'i') { e.preventDefault(); exec('italic') }
    else if (k === 'u') { e.preventDefault(); exec('underline') }
    else if (k === 'k') { e.preventDefault(); promptLink() }
    else if (k === 'z' && !e.shiftKey) { e.preventDefault(); exec('undo') }
    else if ((k === 'z' && e.shiftKey) || k === 'y') { e.preventDefault(); exec('redo') }
  }

  // Lepší paste — bez stylů z Wordu
  const onPaste = (e) => {
    const text = e.clipboardData?.getData('text/html') || e.clipboardData?.getData('text/plain')
    if (!text) return
    e.preventDefault()
    const cleaned = sanitizePastedHtml(text)
    insertHtml(cleaned)
  }

  return (
    <div style={wrapStyle}>
      <Toolbar
        exec={exec}
        setBlock={setBlock}
        isActive={isActive}
        currentBlock={currentBlock}
        promptLink={promptLink}
        promptImage={promptImage}
        togglePlain={togglePlain}
        isHtmlMode={isHtmlMode}
        variables={variables}
        insertHtml={insertHtml}
      />
      {isHtmlMode ? (
        <textarea
          value={htmlDraft}
          onChange={e => { setHtmlDraft(e.target.value); onChange && onChange(e.target.value) }}
          spellCheck={false}
          style={{
            width: '100%', minHeight, padding: 12, outline: 'none', resize: 'vertical',
            border: 'none', borderTop: '1px solid #e2ece7', background: '#0f1a14',
            color: '#a7f3d0', fontFamily: 'ui-monospace,SFMono-Regular,Menlo,monospace',
            fontSize: 12, lineHeight: 1.55,
          }}
        />
      ) : (
        <div
          ref={editorRef}
          contentEditable
          suppressContentEditableWarning
          onInput={emit}
          onBlur={emit}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          data-placeholder={placeholder}
          className="rte-content"
          style={{
            minHeight,
            padding: 14,
            outline: 'none',
            background: '#fff',
            borderTop: '1px solid #e2ece7',
            fontSize: 14,
            lineHeight: 1.6,
            color: '#0f1a14',
            overflowWrap: 'anywhere',
          }}
        />
      )}
      <style>{rteCss}</style>
    </div>
  )
}

function Toolbar({ exec, setBlock, isActive, currentBlock, promptLink, promptImage, togglePlain, isHtmlMode, variables, insertHtml }) {
  const block = currentBlock()
  return (
    <div style={toolbarStyle}>
      {/* Blok / nadpisy */}
      <select
        value={['h1','h2','h3','h4','blockquote','pre'].includes(block) ? block : 'p'}
        onChange={e => setBlock(e.target.value)}
        title="Typ odstavce"
        style={selectStyle}
        disabled={isHtmlMode}
      >
        <option value="p">Odstavec</option>
        <option value="h1">Nadpis 1</option>
        <option value="h2">Nadpis 2</option>
        <option value="h3">Nadpis 3</option>
        <option value="h4">Nadpis 4</option>
        <option value="blockquote">Citace</option>
        <option value="pre">Kód</option>
      </select>

      {/* Font */}
      <select
        defaultValue=""
        onChange={e => { if (e.target.value) exec('fontName', e.target.value); e.target.value = '' }}
        title="Písmo"
        style={selectStyle}
        disabled={isHtmlMode}
      >
        <option value="">Písmo</option>
        <option value="Inter, system-ui, sans-serif">Inter</option>
        <option value="Arial, sans-serif">Arial</option>
        <option value="Georgia, serif">Georgia</option>
        <option value="'Times New Roman', serif">Times</option>
        <option value="'Courier New', monospace">Courier</option>
        <option value="Verdana, sans-serif">Verdana</option>
      </select>

      {/* Velikost */}
      <select
        defaultValue=""
        onChange={e => { if (e.target.value) exec('fontSize', e.target.value); e.target.value = '' }}
        title="Velikost"
        style={{ ...selectStyle, minWidth: 70 }}
        disabled={isHtmlMode}
      >
        <option value="">Velikost</option>
        <option value="1">XS</option>
        <option value="2">S</option>
        <option value="3">M</option>
        <option value="4">L</option>
        <option value="5">XL</option>
        <option value="6">XXL</option>
        <option value="7">XXXL</option>
      </select>

      <Sep />

      <Btn onClick={() => exec('bold')} active={isActive('bold')} disabled={isHtmlMode} title="Tučně (Ctrl+B)"><b>B</b></Btn>
      <Btn onClick={() => exec('italic')} active={isActive('italic')} disabled={isHtmlMode} title="Kurzíva (Ctrl+I)"><i>I</i></Btn>
      <Btn onClick={() => exec('underline')} active={isActive('underline')} disabled={isHtmlMode} title="Podtržení (Ctrl+U)"><span style={{ textDecoration: 'underline' }}>U</span></Btn>
      <Btn onClick={() => exec('strikeThrough')} active={isActive('strikeThrough')} disabled={isHtmlMode} title="Přeškrtnuto"><span style={{ textDecoration: 'line-through' }}>S</span></Btn>

      <Sep />

      <ColorBtn title="Barva textu" onPick={c => exec('foreColor', c)} disabled={isHtmlMode} icon="A" defaultColor="#1a2e22" />
      <ColorBtn title="Zvýraznění" onPick={c => exec('hiliteColor', c)} disabled={isHtmlMode} icon="◼" defaultColor="#fef08a" />

      <Sep />

      <Btn onClick={() => exec('justifyLeft')} active={isActive('justifyLeft')} disabled={isHtmlMode} title="Vlevo">⯇</Btn>
      <Btn onClick={() => exec('justifyCenter')} active={isActive('justifyCenter')} disabled={isHtmlMode} title="Na střed">≡</Btn>
      <Btn onClick={() => exec('justifyRight')} active={isActive('justifyRight')} disabled={isHtmlMode} title="Vpravo">⯈</Btn>
      <Btn onClick={() => exec('justifyFull')} active={isActive('justifyFull')} disabled={isHtmlMode} title="Do bloku">☰</Btn>

      <Sep />

      <Btn onClick={() => exec('insertUnorderedList')} active={isActive('insertUnorderedList')} disabled={isHtmlMode} title="Odrážky">• —</Btn>
      <Btn onClick={() => exec('insertOrderedList')} active={isActive('insertOrderedList')} disabled={isHtmlMode} title="Číslovaný seznam">1.</Btn>
      <Btn onClick={() => exec('outdent')} disabled={isHtmlMode} title="Zmenšit odsazení">⇤</Btn>
      <Btn onClick={() => exec('indent')} disabled={isHtmlMode} title="Zvětšit odsazení">⇥</Btn>

      <Sep />

      <Btn onClick={promptLink} disabled={isHtmlMode} title="Vložit odkaz (Ctrl+K)">🔗</Btn>
      <Btn onClick={() => exec('unlink')} disabled={isHtmlMode} title="Odstranit odkaz">⛓̸</Btn>
      <Btn onClick={promptImage} disabled={isHtmlMode} title="Vložit obrázek (URL)">🖼</Btn>
      <Btn onClick={() => exec('insertHorizontalRule')} disabled={isHtmlMode} title="Vodorovná čára">―</Btn>

      <Sep />

      <Btn onClick={() => exec('removeFormat')} disabled={isHtmlMode} title="Vyčistit formátování">⌫</Btn>
      <Btn onClick={() => exec('undo')} disabled={isHtmlMode} title="Zpět (Ctrl+Z)">↶</Btn>
      <Btn onClick={() => exec('redo')} disabled={isHtmlMode} title="Vpřed (Ctrl+Y)">↷</Btn>

      <div style={{ flex: 1 }} />

      {variables && variables.length > 0 && (
        <select
          defaultValue=""
          onChange={e => { if (e.target.value) insertHtml(e.target.value); e.target.value = '' }}
          title="Vložit proměnnou"
          style={{ ...selectStyle, maxWidth: 220 }}
        >
          <option value="">+ Proměnná…</option>
          {variables.map(v => (
            <option key={v.value} value={v.value}>{v.label}</option>
          ))}
        </select>
      )}

      <Btn onClick={togglePlain} active={isHtmlMode} title="Přepnout na zdrojový HTML">{'</>'}</Btn>
    </div>
  )
}

function Btn({ children, onClick, active, disabled, title }) {
  return (
    <button
      type="button"
      onMouseDown={e => e.preventDefault()} // ať nezmizí selection
      onClick={onClick}
      title={title}
      disabled={disabled}
      style={{
        minWidth: 30, height: 30, padding: '0 8px',
        background: active ? '#74FB71' : '#fff',
        color: active ? '#1a2e22' : '#1a2e22',
        border: '1px solid ' + (active ? '#5fdc5c' : '#d4e8e0'),
        borderRadius: 6, fontSize: 13, fontWeight: 700, cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.45 : 1,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}
    >
      {children}
    </button>
  )
}

function Sep() {
  return <div style={{ width: 1, height: 22, background: '#d4e8e0', margin: '0 2px' }} />
}

function ColorBtn({ onPick, disabled, title, icon, defaultColor }) {
  const id = useRef(`rte-color-${Math.random().toString(36).slice(2)}`)
  return (
    <label
      htmlFor={id.current}
      title={title}
      onMouseDown={e => e.preventDefault()}
      style={{
        minWidth: 30, height: 30, padding: '0 8px',
        background: '#fff', color: '#1a2e22',
        border: '1px solid #d4e8e0', borderRadius: 6,
        fontSize: 13, fontWeight: 700,
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.45 : 1,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}
    >
      <span>{icon}</span>
      <input
        id={id.current}
        type="color"
        defaultValue={defaultColor}
        onChange={e => !disabled && onPick(e.target.value)}
        disabled={disabled}
        style={{
          position: 'absolute', inset: 0, opacity: 0, cursor: disabled ? 'not-allowed' : 'pointer',
        }}
      />
    </label>
  )
}

const wrapStyle = {
  border: '1px solid #d4e8e0',
  borderRadius: 12,
  background: '#fff',
  overflow: 'hidden',
}

const toolbarStyle = {
  display: 'flex',
  flexWrap: 'wrap',
  alignItems: 'center',
  gap: 4,
  padding: 6,
  background: '#f1faf7',
  borderBottom: '1px solid #e2ece7',
}

const selectStyle = {
  height: 30,
  padding: '0 6px',
  background: '#fff',
  border: '1px solid #d4e8e0',
  borderRadius: 6,
  fontSize: 12,
  color: '#1a2e22',
  cursor: 'pointer',
  minWidth: 90,
}

const rteCss = `
.rte-content:empty:before {
  content: attr(data-placeholder);
  color: #9ab3a5;
  pointer-events: none;
}
.rte-content { tab-size: 4; }
.rte-content p { margin: 0 0 10px; }
.rte-content h1 { font-size: 1.8em; font-weight: 800; margin: 14px 0 8px; }
.rte-content h2 { font-size: 1.45em; font-weight: 800; margin: 12px 0 6px; }
.rte-content h3 { font-size: 1.2em; font-weight: 700; margin: 10px 0 6px; }
.rte-content h4 { font-size: 1.05em; font-weight: 700; margin: 8px 0 4px; }
.rte-content ul, .rte-content ol { padding-left: 1.4em; margin: 0 0 10px; }
.rte-content li { margin: 2px 0; }
.rte-content blockquote {
  margin: 8px 0; padding: 8px 12px; border-left: 4px solid #74FB71;
  background: #f1faf7; color: #1a2e22; border-radius: 4px;
}
.rte-content pre {
  background: #0f1a14; color: #a7f3d0; padding: 10px 12px; border-radius: 8px;
  font-family: ui-monospace,SFMono-Regular,Menlo,monospace; font-size: 12px;
  overflow: auto; white-space: pre-wrap;
}
.rte-content a { color: #1d4ed8; text-decoration: underline; }
.rte-content img { max-width: 100%; height: auto; border-radius: 8px; }
.rte-content hr { border: none; border-top: 1px solid #d4e8e0; margin: 12px 0; }
.rte-content table { border-collapse: collapse; }
.rte-content table td, .rte-content table th { border: 1px solid #d4e8e0; padding: 4px 8px; }
`

// — utility —

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function escapeAttr(s) {
  return String(s).replace(/"/g, '&quot;')
}

// Velmi jednoduché čištění vloženého HTML — odstraní script/style, MS Office bloat, inline class/id atd.
function sanitizePastedHtml(html) {
  if (!html) return ''
  let out = String(html)
  // odstraň komentáře
  out = out.replace(/<!--[\s\S]*?-->/g, '')
  // odstraň script/style
  out = out.replace(/<\/?(script|style|meta|link|head|html|body|o:p|xml)[^>]*>/gi, '')
  // odstraň class/style/id atributy a Microsoft-specific
  out = out.replace(/\s+(class|style|id|lang|dir|align|width|height|valign|cellpadding|cellspacing|border|bgcolor)="[^"]*"/gi, '')
  out = out.replace(/\s+mso-[^=]+="[^"]*"/gi, '')
  // odstraň prázdné spany
  out = out.replace(/<span>\s*<\/span>/gi, '')
  return out
}
