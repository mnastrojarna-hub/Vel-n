import { Btn, Chip, txt, num } from './BranchRpiUi'

// ─── Dlaždice „Venek“ v živém stavu zón (status.outdoor, kontrakt §14) ───────
// Venek není dveře — bez Otevřít a signálu. Příkazy light_on/light_off, music_on/music_off, zone_test
// s { zone } = číslo venku z HW mapy (jednotka je pozná, protože zónu dveří s tímto číslem nemá).
// Bez čísla zóny (lokální YAML může `outdoor.zone` vynechat; `configured` ho nevyžaduje) jednotka příkazy
// neadresuje (`_is_outdoor` → zone_not_found) — tlačítka jsou pak vypnutá.
// Hodnoty ze zařízení jdou přes txt()/num() — JSON z jednotky nesmí shodit stránku.

const NO_ZONE_TITLE = 'Venek nemá číslo zóny (hardware.outdoor.zone) — příkazy nelze adresovat'

function OutdoorTile({ o, onSend }) {
  const zoneNo = num(o.zone)
  const noZone = zoneNo == null
  const params = { zone: zoneNo }
  const light = o.light === true
  const music = o.music === true
  const active = o.active === true
  const offIn = light ? num(o.off_in_s) : null
  const out = o.audio_out != null && o.audio_out !== '' ? txt(o.audio_out) : ''
  const manualTxt = o.manual === true ? ' (ručně)' : o.manual === false ? ' (ručně vypnuto)' : ''
  return (
    <div className="p-2 rounded-card" style={{ background: active ? '#dcfce7' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="flex items-center gap-2">
        <span className="font-extrabold" style={{ color: '#0f1a14', fontSize: 15 }}>{txt(o.zone)}</span>
        <span className="font-bold text-sm truncate" style={{ color: '#1a2e22' }} title="Venek — prostor před displejem (zóna bez dveří)">Venek</span>
        <span className="ml-auto"><Chip tone={active ? 'green' : 'gray'} title="Venek je aktivní, dokud běží aspoň jedna relace">{active ? 'relace' : 'klid'}</Chip></span>
      </div>
      <div className="text-[12px] mt-1" style={{ color: '#1a2e22' }}>
        <span className="font-bold">{active ? 'Běží relace (kód zadán)' : 'Bez relace'}</span>
      </div>
      <div className="flex items-center gap-1.5 flex-wrap mt-1 text-[11px]" style={{ color: '#6b8c7a' }}>
        <span>světlo <b style={{ color: light ? '#b45309' : '#6b8c7a' }}>{light ? 'svítí' : 'zhasnuto'}</b>{manualTxt}{offIn != null ? ` · zhasne za ${offIn} s` : ''}</span>
        <span>· hudba <b style={{ color: music ? '#1a8a18' : '#6b8c7a' }}>{music ? 'hraje' : 'ne'}</b></span>
        <span>· výstup {out || '—'}</span>
        {o.light_ref != null && <span>· relé {txt(o.light_ref)}</span>}
      </div>
      <div className="flex items-center gap-1 flex-wrap mt-2 pt-2" style={{ borderTop: '1px dashed #d4e8e0' }}>
        <Btn tone={light ? 'amber' : 'gray'} small disabled={noZone}
          title={noZone ? NO_ZONE_TITLE : light ? 'Zhasnout venkovní světlo (do další relace)' : 'Rozsvítit venkovní světlo (drží do vypnutí nebo do další relace — pak zhasne po doběhu)'}
          onClick={() => onSend(light ? 'light_off' : 'light_on', params, `světlo ${light ? '⏹' : '▶'} (venek, zóna ${txt(zoneNo)})`)}>
          Světlo {light ? '⏹' : '▶'}
        </Btn>
        <Btn tone={music ? 'red' : 'green'} small disabled={noZone}
          title={noZone ? NO_ZONE_TITLE : out ? (music ? 'Zastavit hudbu venku' : 'Spustit hudbu venku (hraje do zastavení / doběhu)') : 'Venek nemá audio výstup (hudba venku jen v režimu multi)'}
          onClick={() => onSend(music ? 'music_off' : 'music_on', params, `hudba ${music ? '⏹' : '▶'} (venek, zóna ${txt(zoneNo)})`)}>
          Hudba {music ? '⏹' : '▶'}
        </Btn>
        <Btn tone="blue" small disabled={noZone} title={noZone ? NO_ZONE_TITLE : 'Test venkovního světla (1 s) a hudby venku (3 s, jen multi); při běžící relaci jednotka test odmítne'}
          onClick={() => onSend('zone_test', params, `test venku (zóna ${txt(zoneNo)})`)}>Test</Btn>
      </div>
    </div>
  )
}

export { OutdoorTile }
