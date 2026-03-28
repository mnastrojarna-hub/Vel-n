import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'

export default function CustomerVerificationSection({ vs, profile }) {
  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>Overeni dokladu zakaznika</h3>
      <div className="space-y-3 mb-4">
        <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2">
            <span style={{ fontSize: 14 }}>{vs.hasLicense ? '✅' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ridicsky prukaz (RP)</span>
            <Badge label={vs.hasLicense ? 'Vyfoceno' : 'Chybi'} color={vs.hasLicense ? '#1a8a18' : '#dc2626'} bg={vs.hasLicense ? '#dcfce7' : '#fee2e2'} />
          </div>
          <div className="flex flex-wrap gap-2">
            <Badge
              label={vs.licenseValid ? `Platny do ${profile?.license_expiry}` : profile?.license_expiry ? `Expirovany (${profile.license_expiry})` : 'Platnost nevyplnena'}
              color={vs.licenseValid ? '#1a8a18' : '#dc2626'}
              bg={vs.licenseValid ? '#dcfce7' : '#fee2e2'}
            />
            <Badge
              label={vs.licenseGroupFilled ? `Skupiny: ${(profile?.license_group || []).join(', ')}` : 'Skupiny nevyplneny'}
              color={vs.licenseGroupFilled ? '#1a8a18' : '#b45309'}
              bg={vs.licenseGroupFilled ? '#dcfce7' : '#fef3c7'}
            />
            {vs.licenseGroupFilled && profile?.license_group && (
              <Badge
                label={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? 'Skupina pro motorky OK' : 'Chybi skupina A/A2/A1'}
                color={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#1a8a18' : '#dc2626'}
                bg={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#dcfce7' : '#fee2e2'}
              />
            )}
          </div>
        </div>

        <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2">
            <span style={{ fontSize: 14 }}>{vs.hasIdentity ? '✅' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Doklad totoznosti (OP nebo pas)</span>
            <Badge label={vs.hasIdentity ? 'Vyfoceno' : 'Chybi'} color={vs.hasIdentity ? '#1a8a18' : '#dc2626'} bg={vs.hasIdentity ? '#dcfce7' : '#fee2e2'} />
          </div>
          {vs.hasIdentity && (
            <div className="flex gap-2">
              {vs.hasIdCard && <Badge label="Obcansky prukaz" color="#1a8a18" bg="#dcfce7" />}
              {vs.hasPassport && <Badge label="Cestovni pas" color="#1a8a18" bg="#dcfce7" />}
            </div>
          )}
        </div>
      </div>

      <div className="p-3 rounded-lg" style={{ background: vs.allOk ? '#dcfce7' : '#fef3c7', border: `1px solid ${vs.allOk ? '#86efac' : '#fcd34d'}` }}>
        <div className="flex items-center gap-2">
          <span style={{ fontSize: 16 }}>{vs.allOk ? '✅' : '⚠️'}</span>
          <span className="text-sm font-bold" style={{ color: vs.allOk ? '#1a8a18' : '#b45309' }}>
            {vs.allOk ? 'Vsechny doklady overeny — kody k boxu mohou byt uvolneny' : 'Doklady neuplne — kody k boxu NELZE uvolnit'}
          </span>
        </div>
        {!vs.allOk && (
          <ul className="mt-2 space-y-1" style={{ fontSize: 12, color: '#92400e' }}>
            {!vs.hasLicense && <li>• Chybi vyfoceny ridicsky prukaz</li>}
            {vs.hasLicense && !vs.licenseValid && <li>• Ridicsky prukaz je neplatny nebo expirovany</li>}
            {vs.hasLicense && !vs.licenseGroupFilled && <li>• Ridicske skupiny nejsou vyplneny v profilu</li>}
            {vs.hasLicense && vs.licenseGroupFilled && !profile?.license_group?.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) && <li>• Zakaznik nema ridicskou skupinu pro motorky (A/A2/A1/AM)</li>}
            {!vs.hasIdentity && <li>• Chybi vyfoceny doklad totoznosti (OP nebo pas)</li>}
          </ul>
        )}
      </div>
    </Card>
  )
}
