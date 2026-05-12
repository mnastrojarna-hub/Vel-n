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
  maxHeight = null, // pokud zadáno, contenteditable má vlastní scroll a toolbar zůstává nahoře
  variables = null, // volitelné: pole {label, value} tlačítek pro vložení proměnné
}) {
  const editorRef = useRef(null)
  const [isHtmlMode, setIsHtmlMode] = useState(false)
  const [htmlDraft, setHtmlDraft] = useState('')
  const [, force] = useState(0)
  const lastValueRef = useRef('')
  // Poslední platný výběr (Range) UVNITŘ editoru. Když uživatel klikne na lištu —
  // hlavně na <input type=color> (otevře nativní dialog) nebo na <select> — editor
  // ztratí focus a výběr se sbalí; bez tohohle by `execCommand('foreColor'…)` nemělo
  // na čem pracovat → barva/formátování se „neuložilo". Range si tu uchováme a před
  // každým exec() ho obnovíme.
  const savedRangeRef = useRef(null)

  // Ulož aktuální výběr, pokud je uvnitř editoru.
  const captureSelection = useCallback(() => {
    const el = editorRef.current
    if (!el) return
    const sel = window.getSelection && window.getSelection()
    if (!sel || sel.rangeCount === 0) return
    const r = sel.getRangeAt(0)
    if (el.contains(r.commonAncestorContainer)) {
      savedRangeRef.current = r.cloneRange()
    }
  }, [])

  // Obnov uložený výběr (nepřepisuje platný neprázdný výběr, který v editoru pořád je).
  const restoreSelection = useCallback(() => {
    const el = editorRef.current
    if (!el) return
    try { el.focus({ preventScroll: true }) } catch (_) { el.focus() }
    const sel = window.getSelection && window.getSelection()
    if (!sel) return
    const cur = sel.rangeCount ? sel.getRangeAt(0) : null
    if (cur && !cur.collapsed && el.contains(cur.commonAncestorContainer)) return
    const saved = savedRangeRef.current
    if (saved && el.contains(saved.commonAncestorContainer)) {
      try { sel.removeAllRanges(); sel.addRange(saved) } catch (_) { /* ignore */ }
    }
  }, [])

  // Sync vnější `value` → editor (jen když se opravdu liší od aktuálního obsahu)
  useEffect(() => {
    if (isHtmlMode) return
    const el = editorRef.current
    if (!el) return
    if (value !== lastValueRef.current && value !== el.innerHTML) {
      el.innerHTML = value || ''
      lastValueRef.current = value || ''
      savedRangeRef.current = null
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
    restoreSelection()
    try {
      // styleWithCSS=true → foreColor/hiliteColor produce <span style> instead of <font>
      try { document.execCommand('styleWithCSS', false, true) } catch (_) {}
      document.execCommand(cmd, false, val)
      // Browsers may still emit <b>/<i>/<font>; normalize to semantic tags.
      replaceLegacyTags(editorRef.current)
    } catch (_) { /* ignore */ }
    captureSelection()
    emit()
  }, [emit, restoreSelection, captureSelection])

  const insertHtml = useCallback((html) => {
    restoreSelection()
    try {
      document.execCommand('insertHTML', false, html)
    } catch (_) { /* ignore */ }
    captureSelection()
    emit()
  }, [emit, restoreSelection, captureSelection])

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

  // Lepší paste — bez stylů z Wordu, plain text převedený na odstavce
  const onPaste = (e) => {
    const html = e.clipboardData?.getData('text/html')
    const plain = e.clipboardData?.getData('text/plain')
    if (!html && !plain) return
    e.preventDefault()
    const cleaned = html ? sanitizePastedHtml(html) : plainTextToHtml(plain)
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
        captureSelection={captureSelection}
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
            ...(maxHeight ? { maxHeight, overflow: 'auto' } : {}),
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
          onKeyUp={captureSelection}
          onMouseUp={captureSelection}
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
            ...(maxHeight ? { maxHeight, overflowY: 'auto' } : {}),
          }}
        />
      )}
      <style>{rteCss}</style>
    </div>
  )
}

function Toolbar({ exec, setBlock, isActive, currentBlock, promptLink, promptImage, togglePlain, isHtmlMode, variables, insertHtml, captureSelection }) {
  const block = currentBlock()
  return (
    // onMouseDown v capture fázi: jakmile uživatel sáhne na lištu (barva / select /
    // tlačítko), uložíme aktuální výběr v editoru DŘÍV, než klik přesune focus / otevře
    // nativní dialog. exec() ho pak před příkazem obnoví → barva i ostatní formátování
    // se aplikuje na to, co bylo vybrané.
    <div style={toolbarStyle} onMouseDownCapture={() => captureSelection && captureSelection()}>
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

      <Btn onClick={() => exec('bold')} active={isActive('bold')} disabled={isHtmlMode} title="Tučně (Ctrl+B)"><strong>B</strong></Btn>
      <Btn onClick={() => exec('italic')} active={isActive('italic')} disabled={isHtmlMode} title="Kurzíva (Ctrl+I)"><em>I</em></Btn>
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
          title="Vložit proměnnou (placeholder)"
          style={{
            ...selectStyle,
            maxWidth: 240,
            background: '#74FB71',
            color: '#0f1a14',
            border: '1px solid #5fdc5c',
            fontWeight: 800,
          }}
        >
          <option value="">+ Proměnná ({variables.length})</option>
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
  position: 'relative',
}

const toolbarStyle = {
  display: 'flex',
  flexWrap: 'wrap',
  alignItems: 'center',
  gap: 4,
  padding: 6,
  background: '#f1faf7',
  borderBottom: '1px solid #e2ece7',
  borderTopLeftRadius: 12,
  borderTopRightRadius: 12,
  position: 'sticky',
  top: 0,
  zIndex: 5,
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

// Shared CSS pro editor i preview iframe — co vidíš v editoru = co se vyrenderuje
// jako PDF přes PDFShift. Exportováno přes `rteContentCss` níž.
const rteCss = `
.rte-content:empty:before {
  content: attr(data-placeholder);
  color: #9ab3a5;
  pointer-events: none;
}
.rte-content { tab-size: 4; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; line-height: 1.6; color: #0f1a14; }
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

// Export CSS pravidel + helper, který obalí HTML obsah do plného dokumentu pro
// `iframe srcDoc`, takže náhled vypadá identicky jako editor.
export const rteContentCss = rteCss
export function buildPreviewHtml(content) {
  const safe = content || '<p style="color:#9ab3a5">Prázdný obsah</p>'
  return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><style>
html,body { margin: 0; padding: 24px; background: #fff; }
${rteCss}
</style></head><body class="rte-content">${safe}</body></html>`
}

// — utility —

// Konvertuje legacy <b>/<i>/<font> tagy v rámci editovaného uzlu na sémantické
// <strong>/<em>/<span style>. execCommand v některých prohlížečích produkuje
// nesémantické tagy i když styleWithCSS=true.
function replaceLegacyTags(root) {
  if (!root || !root.querySelectorAll) return
  const swap = (fromSel, toTag) => {
    root.querySelectorAll(fromSel).forEach(n => {
      const r = document.createElement(toTag)
      while (n.firstChild) r.appendChild(n.firstChild)
      if (n.getAttribute && n.getAttribute('style')) r.setAttribute('style', n.getAttribute('style'))
      if (n.getAttribute && n.getAttribute('class')) r.setAttribute('class', n.getAttribute('class'))
      n.parentNode.replaceChild(r, n)
    })
  }
  swap('b', 'strong')
  swap('i', 'em')
  // <font color="#xxx" size="N" face="..." style="..."> → <span style="...">
  root.querySelectorAll('font').forEach(n => {
    const span = document.createElement('span')
    const styles = []
    const color = n.getAttribute('color')
    const face = n.getAttribute('face')
    const inline = n.getAttribute('style')
    if (color) styles.push('color: ' + color)
    if (face) styles.push('font-family: ' + face)
    if (inline) styles.push(inline)
    if (styles.length) span.setAttribute('style', styles.join('; '))
    if (n.getAttribute('class')) span.setAttribute('class', n.getAttribute('class'))
    while (n.firstChild) span.appendChild(n.firstChild)
    n.parentNode.replaceChild(span, n)
  })
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
function escapeAttr(s) {
  return String(s).replace(/"/g, '&quot;')
}

// Plain text → HTML s odstavci a <br> (zachová zalomení řádků a prázdné řádky)
function plainTextToHtml(text) {
  if (!text) return ''
  const blocks = String(text).replace(/\r\n/g, '\n').split(/\n{2,}/)
  return blocks.map(b => {
    const lines = b.split('\n').map(escapeHtml)
    return `<p>${lines.join('<br>')}</p>`
  }).join('')
}

// Čištění vloženého HTML (typicky z Wordu / Google Docs).
// Cíl: zachovat formátování 1:1 — písmo, velikost, tučné/kurzíva/podtržení, barvy,
// zarovnání, odsazení, tabulky, šířky sloupců — ale vyhodit nebezpečné věci
// (script, event handlery, externí odkazy na CSS) a Word „bloat" (mso-*, o:p, prázdné spany).
const SAFE_CSS_PROPS = new Set([
  'color', 'background', 'background-color',
  'font', 'font-family', 'font-size', 'font-weight', 'font-style', 'font-variant', 'letter-spacing', 'word-spacing',
  'text-align', 'text-decoration', 'text-decoration-line', 'text-decoration-color', 'text-decoration-style',
  'text-indent', 'text-transform', 'text-shadow', 'line-height', 'vertical-align', 'white-space', 'direction',
  'margin', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
  'border', 'border-top', 'border-right', 'border-bottom', 'border-left',
  'border-color', 'border-style', 'border-width', 'border-collapse', 'border-spacing', 'border-radius',
  'width', 'min-width', 'max-width', 'height', 'min-height',
  'list-style', 'list-style-type', 'list-style-position',
  'float', 'clear', 'display',
])
const ALLOWED_TAGS = new Set([
  'p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 'u', 's', 'strike', 'del', 'ins', 'sub', 'sup', 'small', 'mark',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'code', 'hr',
  'ul', 'ol', 'li', 'a', 'img',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'caption', 'colgroup', 'col',
  'figure', 'figcaption',
])
const ALLOWED_ATTRS = new Set(['style', 'href', 'src', 'alt', 'title', 'colspan', 'rowspan', 'span', 'target', 'rel', 'start', 'type'])

function cleanStyle(value) {
  if (!value) return ''
  const kept = []
  String(value).split(';').forEach(decl => {
    const idx = decl.indexOf(':')
    if (idx < 0) return
    const prop = decl.slice(0, idx).trim().toLowerCase()
    let val = decl.slice(idx + 1).trim()
    if (!prop || !val) return
    if (prop.startsWith('mso-') || prop.startsWith('-')) return
    if (!SAFE_CSS_PROPS.has(prop)) return
    // display:none by skryl obsah — neměňme viditelnost
    if (prop === 'display' && /none/i.test(val)) return
    // url(...) ve stylech pryč (kvůli bezpečnosti)
    if (/url\s*\(/i.test(val)) return
    if (/expression\s*\(|javascript:/i.test(val)) return
    val = val.replace(/\s+/g, ' ').trim()
    kept.push(prop + ': ' + val)
  })
  return kept.join('; ')
}

const FONT_SIZE_MAP = { 1: '10px', 2: '13px', 3: '16px', 4: '18px', 5: '24px', 6: '32px', 7: '48px' }

function sanitizeNode(node) {
  if (node.nodeType === 3) return // text — nech být
  if (node.nodeType === 8) { node.remove?.(); return } // komentář
  if (node.nodeType !== 1) { node.remove?.(); return }
  const tag = node.tagName.toLowerCase()

  // úplně nebezpečné / Word-only elementy → smazat i s obsahem
  if (['script', 'style', 'link', 'meta', 'head', 'title', 'iframe', 'object', 'embed', 'noscript', 'xml', 'o:p'].includes(tag)
      || tag.includes(':')) {
    node.remove(); return
  }

  // nejdřív zpracuj děti (depth-first), pak řeš tenhle uzel
  Array.from(node.childNodes).forEach(child => sanitizeNode(child))

  const parent = node.parentNode
  if (!parent) return

  // nepovolený obal → rozbal (případně mapuj <font>/<center> na <span style>)
  if (!ALLOWED_TAGS.has(tag)) {
    let mappedStyle = ''
    if (tag === 'font') {
      const c = node.getAttribute('color'); const f = node.getAttribute('face'); const sz = node.getAttribute('size')
      if (c) mappedStyle += `color:${c};`
      if (f) mappedStyle += `font-family:${f};`
      if (sz && FONT_SIZE_MAP[sz]) mappedStyle += `font-size:${FONT_SIZE_MAP[sz]};`
    }
    if (tag === 'center') mappedStyle += 'text-align:center;'
    const inline = cleanStyle(node.getAttribute && node.getAttribute('style'))
    mappedStyle += inline ? (inline.endsWith(';') ? inline : inline + ';') : ''
    if (mappedStyle) {
      const span = node.ownerDocument.createElement('span')
      span.setAttribute('style', mappedStyle)
      while (node.firstChild) span.appendChild(node.firstChild)
      parent.replaceChild(span, node)
    } else {
      while (node.firstChild) parent.insertBefore(node.firstChild, node)
      parent.removeChild(node)
    }
    return
  }

  // atributy: nech jen povolené, style profiltruj
  Array.from(node.attributes || []).forEach(attr => {
    const name = attr.name.toLowerCase()
    if (!ALLOWED_ATTRS.has(name) || name.startsWith('on')) { node.removeAttribute(attr.name); return }
    if (name === 'style') {
      const cleaned = cleanStyle(attr.value)
      if (cleaned) node.setAttribute('style', cleaned)
      else node.removeAttribute('style')
      return
    }
    if ((name === 'href' || name === 'src') && /^\s*(javascript:|data:text\/html|vbscript:)/i.test(attr.value)) {
      node.removeAttribute(attr.name)
    }
  })

  if (tag === 'a' && node.getAttribute('href')) {
    node.setAttribute('rel', 'noopener')
    if (!node.getAttribute('target')) node.setAttribute('target', '_blank')
  }
}

function sanitizePastedHtml(html) {
  if (!html) return ''
  // Word balí část obsahu do conditional comments <!--[if ...]> ... <![endif]-->
  let src = String(html)
    .replace(/<!--\[if[\s\S]*?<!\[endif\]-->/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
  let doc
  try { doc = new DOMParser().parseFromString(src, 'text/html') } catch (_) { return src.replace(/<[^>]+>/g, '') }
  const body = doc.body || doc
  Array.from(body.childNodes).forEach(child => sanitizeNode(child))
  let out = body.innerHTML
  // úklid prázdných obalů
  out = out.replace(/<span[^>]*>(\s|&nbsp;)*<\/span>/gi, m => (/&nbsp;|\s/.test(m) ? ' ' : ''))
  out = out.replace(/(\s|&nbsp;)*<p[^>]*>(\s|&nbsp;|<br\s*\/?>)*<\/p>/gi, '')
  return out.trim()
}
