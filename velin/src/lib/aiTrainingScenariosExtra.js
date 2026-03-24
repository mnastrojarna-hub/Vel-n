// AI Training Scenarios Part 2 — SOS, e-shop, profile, compliance, analytics
import { TS, NAME, SURNAME, BRANCH, MOTO, DAYS, EXTRAS } from './aiTrainingHelpers'

export const SCENARIOS_EXTRA = [
  {
    id: 'sos_incident', name: 'SOS — porucha', icon: '🚨',
    agents: ['sos','service','fleet'],
    generate: () => {
      const fn = NAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř test zákazníka ${fn} Novák, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} hlásí poruchu ${moto} na silnici. GPS: 50.08°N, 14.42°E. Vytvoř SOS.`, agent: 'sos', tool: 'update_sos_incident' },
        { msg: `Ukaž aktivní SOS incidenty. Stav posledního?`, agent: 'sos', tool: 'get_sos_incidents' },
        { msg: `Motorka potřebuje servis. Vytvoř servisní zakázku.`, agent: 'service', tool: 'create_service_order' },
        { msg: `SOS vyřešen — zákazník dostal náhradní. Uzavři.`, agent: 'sos', tool: 'resolve_sos' },
      ]
    },
  },
  {
    id: 'sos_flat_tire', name: 'SOS — defekt pneu', icon: '🛞',
    agents: ['sos','service','fleet'],
    generate: () => {
      const fn = NAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř test zákazníka ${fn}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} hlásí defekt zadní pneu na ${moto}. GPS: 50.05°N, 14.45°E.`, agent: 'sos', tool: 'update_sos_incident' },
        { msg: `Objednej odtah ${moto} na pobočku. Přiřaď technika.`, agent: 'sos', tool: 'assign_sos' },
        { msg: `${fn} dostane náhradní motorku.`, agent: 'sos', tool: 'update_sos_incident' },
        { msg: `Servisní zakázka: výměna zadní pneu na ${moto}.`, agent: 'service', tool: 'create_service_order' },
        { msg: `SOS vyřešen. Uzavři incident.`, agent: 'sos', tool: 'resolve_sos' },
      ]
    },
  },
  {
    id: 'sos_accident', name: 'SOS — nehoda', icon: '💥',
    agents: ['sos','fleet','service'],
    generate: () => {
      const fn = NAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř test zákazníka ${fn}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `URGENTNÍ: ${fn} měl nehodu s ${moto} na D1 km 45. Motorka nepojízdná. Kritický SOS.`, agent: 'sos', tool: 'update_sos_incident' },
        { msg: `Zajisti odtah ${moto}. Přiřaď technika.`, agent: 'sos', tool: 'assign_sos' },
        { msg: `${moto}: poškozený rám + vidlice. Servisní zakázka: oprava po nehodě.`, agent: 'service', tool: 'create_service_order' },
        { msg: `Stav ${moto} na "damaged" — nepůjčovat.`, agent: 'fleet', tool: 'update_motorcycle' },
        { msg: `Nehoda vyřešena. Uzavři SOS: pojistná událost.`, agent: 'sos', tool: 'resolve_sos' },
      ]
    },
  },
  {
    id: 'sos_theft', name: 'SOS — krádež', icon: '🔒',
    agents: ['sos','fleet'],
    generate: () => {
      const fn = NAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř test zákazníka ${fn}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} hlásí odcizení ${moto} z parkoviště Brno. GPS: 49.19°N, 16.61°E.`, agent: 'sos', tool: 'update_sos_incident' },
        { msg: `Zkontroluj GPS lokaci ${moto}.`, agent: 'fleet', tool: 'get_fleet_overview' },
        { msg: `Označ ${moto} jako "stolen". Zablokuj pro půjčování.`, agent: 'fleet', tool: 'update_motorcycle' },
        { msg: `Krádež zpracována, policie informována. Uzavři SOS.`, agent: 'sos', tool: 'resolve_sos' },
      ]
    },
  },
  {
    id: 'eshop_purchase', name: 'E-shop s promo kódem', icon: '🛒',
    agents: ['eshop','finance'],
    generate: () => {
      const tag = TS()
      return [
        { msg: `Ukaž produkty v e-shopu.`, agent: 'eshop', tool: 'get_accessory_types' },
        { msg: `Vytvoř promo kód SIMTEST${tag} se slevou 15%.`, agent: 'eshop', tool: 'create_promo_code' },
        { msg: `Aktivní promo kódy a vouchery? Kolik platných?`, agent: 'finance', tool: 'get_vouchers_and_promos' },
        { msg: `Zákazník objednal helmu + rukavice s kódem SIMTEST${tag}.`, agent: 'eshop', tool: 'update_shop_order' },
      ]
    },
  },
  {
    id: 'eshop_full_order', name: 'E-shop — kompletní objednávka', icon: '📦',
    agents: ['eshop','finance','customers'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS()
      return [
        { msg: `Vytvoř test zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} prohlíží e-shop — dostupné produkty?`, agent: 'eshop', tool: 'get_accessory_types' },
        { msg: `${fn} objednává: helma L + rukavice M + bunda XL. Doručení Brno.`, agent: 'eshop', tool: 'update_shop_order' },
        { msg: `${fn} mění adresu doručení na Praha 3, Žižkov 12.`, agent: 'eshop', tool: 'update_shop_order' },
        { msg: `Objednávka zaplacena. Faktura pro ${fn}.`, agent: 'finance', tool: 'get_invoices' },
        { msg: `Objednávka odeslána. Stav na "shipped".`, agent: 'eshop', tool: 'update_shop_order' },
      ]
    },
  },
  {
    id: 'profile_changes', name: 'Profil — změna údajů a hesla', icon: '👤',
    agents: ['customers'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS()
      return [
        { msg: `Vytvoř test zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz, adresa Brno.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} mění adresu na Praha 5, Plzeňská 100.`, agent: 'customers', tool: 'update_customer' },
        { msg: `${fn} mění telefon na +420 666 ${tag} 222.`, agent: 'customers', tool: 'update_customer' },
        { msg: `Ověř profil ${fn} — jsou údaje aktuální?`, agent: 'customers', tool: 'get_customer_detail' },
      ]
    },
  },
  {
    id: 'service_maintenance', name: 'Servis — údržba', icon: '🔧',
    agents: ['fleet','service'],
    generate: () => {
      const moto = MOTO()
      return [
        { msg: `Které motorky potřebují servis? Použij get_service_status.`, agent: 'service', tool: 'get_service_status' },
        { msg: `Naplánuj servis ${moto}: výměna oleje + brzdy.`, agent: 'service', tool: 'create_service_order' },
        { msg: `Stav skladu — olej a brzdové destičky?`, agent: 'service', tool: 'get_inventory' },
        { msg: `Servis ${moto} hotov. Zapiš: výměna oleje, 1.5h.`, agent: 'service', tool: 'create_maintenance_log' },
        { msg: `${moto} po servisu ready. Stav na "available".`, agent: 'fleet', tool: 'update_motorcycle' },
      ]
    },
  },
  {
    id: 'hr_shift', name: 'HR — směny a docházka', icon: '👷',
    agents: ['hr'],
    generate: () => [
      { msg: `Přehled zaměstnanců. Kdo je dnes ve směně?`, agent: 'hr', tool: 'get_employees' },
      { msg: `Docházka za tento týden. Absence?`, agent: 'hr', tool: 'get_attendance_overview' },
      { msg: `Nevyřízené žádosti o dovolenou?`, agent: 'hr', tool: 'get_pending_vacations' },
      { msg: `Plán směn příští týden. Pokryté pobočky?`, agent: 'hr', tool: 'get_shifts_overview' },
    ],
  },
  {
    id: 'analytics_review', name: 'Analytický přehled', icon: '📊',
    agents: ['analytics','finance'],
    generate: () => [
      { msg: `Výkon poboček za měsíc. Nejlepší?`, agent: 'analytics', tool: 'analyze_branch_performance' },
      { msg: `Ranking motorek podle vytíženosti.`, agent: 'analytics', tool: 'analyze_motorcycle_performance' },
      { msg: `Predikce poptávky příští týden.`, agent: 'analytics', tool: 'forecast_predictions' },
      { msg: `Tržby, náklady, zisk za měsíc.`, agent: 'finance', tool: 'get_financial_overview' },
    ],
  },
  {
    id: 'communication_check', name: 'Kontrola komunikace', icon: '📬',
    agents: ['customers','cms','finance'],
    generate: () => [
      { msg: `Nevyřízené zprávy od zákazníků?`, agent: 'customers', tool: 'get_messages_overview' },
      { msg: `Aktivní emailové šablony? booking_reserved, booking_completed?`, agent: 'cms', tool: 'get_message_templates' },
      { msg: `Notifikační log — odešly všechny? Chyby?`, agent: 'customers', tool: 'get_notification_log' },
      { msg: `Faktury mají správné IČO, DIČ, adresu?`, agent: 'finance', tool: 'get_invoices' },
      { msg: `Dokumenty aktuální — VOP, smlouva, protokol?`, agent: 'cms', tool: 'get_documents' },
    ],
  },
  {
    id: 'invoice_matching', name: 'Párování faktur', icon: '🧾',
    agents: ['finance'],
    generate: () => [
      { msg: `Nezaplacené faktury? Celková dlužná částka?`, agent: 'finance', tool: 'get_invoices' },
      { msg: `Nepárované dodací listy?`, agent: 'finance', tool: 'get_financial_overview' },
      { msg: `Účetní záznamy za měsíc. Sedí příjmy a výdaje?`, agent: 'finance', tool: 'get_accounting_entries' },
      { msg: `DPH přehled — stav za aktuální období?`, agent: 'finance', tool: 'get_vat_returns' },
    ],
  },
  {
    id: 'cms_check', name: 'CMS a nastavení', icon: '🌐',
    agents: ['cms'],
    generate: () => [
      { msg: `CMS nastavení — banner, kontakty, feature flagy.`, agent: 'cms', tool: 'get_cms_settings' },
      { msg: `Aktivní emailové šablony?`, agent: 'cms', tool: 'get_message_templates' },
      { msg: `Smlouvy a dokumenty — aktuální VOP a smlouva?`, agent: 'cms', tool: 'get_contracts' },
    ],
  },
  {
    id: 'government_compliance', name: 'Státní správa', icon: '🏛️',
    agents: ['government','fleet'],
    generate: () => [
      { msg: `STK a pojistky flotily. Co expiruje v 30 dnech?`, agent: 'government', tool: 'get_government_overview' },
      { msg: `Detail flotily — registrace, VIN, pojištění.`, agent: 'fleet', tool: 'get_fleet_overview' },
    ],
  },
  // --- EDGE CASES ---
  {
    id: 'wrong_license', name: 'Rezervace bez platného ŘP', icon: '🚫',
    agents: ['bookings','customers'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS()
      return [
        { msg: `Vytvoř test zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz. BEZ nahraného řidičského průkazu.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} chce rezervovat ${MOTO()} (kat. A2) ale nemá nahrané doklady. Zkontroluj a odmítni nebo upozorni.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Zkontroluj profil ${fn} — jsou nahrány řidičský průkaz a OP? Použij get_customer_detail.`, agent: 'customers', tool: 'get_customer_detail' },
        { msg: `Pošli ${fn} zprávu: "Nahrajte prosím ŘP a OP pro dokončení rezervace."`, agent: 'customers', tool: 'send_customer_message' },
      ]
    },
  },
  {
    id: 'missing_docs', name: 'Chybějící doklady při rezervaci', icon: '📄',
    agents: ['bookings','customers'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS()
      return [
        { msg: `Vytvoř test zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} má ŘP ale chybí občanský průkaz. Může dokončit rezervaci? Zkontroluj.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Jaké doklady má ${fn} nahrané? Které chybí?`, agent: 'customers', tool: 'get_customer_detail' },
        { msg: `Informuj ${fn}: chybí OP, bez něj nelze vydat motorku.`, agent: 'customers', tool: 'send_customer_message' },
      ]
    },
  },
  {
    id: 'duplicate_booking', name: 'Duplicitní/překrývající se rezervace', icon: '⚠️',
    agents: ['bookings','fleet'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO(), br = BRANCH()
      return [
        { msg: `Vytvoř test zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} rezervuje ${moto} v ${br} od ${DAYS(3)} do ${DAYS(6)}.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `${fn} ${ln} se pokouší o DRUHOU rezervaci ve stejném termínu — jiná motorka, ale překryv. Jak systém reaguje?`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Zkontroluj overlap — má ${fn} aktivní rezervace které se překrývají?`, agent: 'bookings', tool: 'get_bookings_detail' },
      ]
    },
  },
  {
    id: 'moto_overlap', name: 'Motorka rezervovaná dvakrát', icon: '🏍️',
    agents: ['bookings','fleet'],
    generate: () => {
      const moto = MOTO(), br = BRANCH(), tag = TS()
      return [
        { msg: `Vytvoř 2 test zákazníky: A test.sim.a${tag}@motogo24.cz, B test.sim.b${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `Zákazník A rezervuje ${moto} v ${br} od ${DAYS(3)} do ${DAYS(6)}.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Zákazník B se pokouší o stejnou ${moto} ve ${br} od ${DAYS(4)} do ${DAYS(7)}. Zjisti overlap.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Zkontroluj dostupnost ${moto} — je správně blokovaná pro zákazníka A?`, agent: 'fleet', tool: 'get_motorcycle_detail' },
      ]
    },
  },
]
