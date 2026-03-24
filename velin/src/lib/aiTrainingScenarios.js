// AI Training Scenarios Part 1 — core customer journeys
// Each scenario simulates real customer process step by step
import { TS, NAME, SURNAME, BRANCH, MOTO, DAYS, EXTRAS } from './aiTrainingHelpers'

export const SCENARIOS_CORE = [
  {
    id: 'happy_path', name: 'Kompletní rezervace', icon: '😊',
    agents: ['customers','bookings','fleet','finance'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), br = BRANCH(), moto = MOTO()
      return [
        { msg: `Vytvoř testovacího zákazníka: ${fn} ${ln}, email test.sim.${tag}@motogo24.cz, tel +420777${tag}111. Použij create_test_user.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} si prohlíží motorky v pobočce ${br}. Ukaž flotilu přes get_fleet_overview.`, agent: 'fleet', tool: 'get_fleet_overview' },
        { msg: `${fn} ${ln} chce rezervovat ${moto} v ${br} od ${DAYS(3)} do ${DAYS(6)}.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `${fn} si přidává extra: ${EXTRAS()}. Uprav detaily rezervace.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `${fn} ${ln} zaplatil zálohu. Potvrď platbu poslední rezervace.`, agent: 'bookings', tool: 'confirm_booking_payment' },
        { msg: `Finanční přehled dnešního dne — rezervace, tržby.`, agent: 'finance', tool: 'get_financial_overview' },
      ]
    },
  },
  {
    id: 'cancellation', name: 'Storno rezervace', icon: '❌',
    agents: ['customers','bookings','finance'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS()
      return [
        { msg: `Vytvoř testovacího zákazníka: ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} chce zarezervovat ${MOTO()} v ${BRANCH()} od ${DAYS(5)} do ${DAYS(8)}.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `${fn} ${ln} ruší rezervaci. Důvod: změna plánů. Zpracuj storno + poplatek.`, agent: 'bookings', tool: 'cancel_booking' },
        { msg: `Stornované rezervace za dnešek. Storno rate?`, agent: 'analytics', tool: 'get_bookings_summary' },
      ]
    },
  },
  {
    id: 'cancel_and_rebook', name: 'Storno + nová rezervace', icon: '🔄',
    agents: ['bookings','customers','finance'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), m1 = MOTO(), m2 = MOTO()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} rezervuje ${m1} v ${BRANCH()} od ${DAYS(4)} do ${DAYS(7)}.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `${fn} ${ln} ruší ${m1} — chce jinou motorku.`, agent: 'bookings', tool: 'cancel_booking' },
        { msg: `${fn} ${ln} místo toho chce ${m2} ve stejném termínu.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Stav refundu za zrušenou + nová platba za ${m2}.`, agent: 'finance', tool: 'get_financial_overview' },
      ]
    },
  },
  {
    id: 'extend_booking', name: 'Prodloužení výpůjčky', icon: '⏩',
    agents: ['bookings','fleet','finance'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO(), br = BRANCH()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} má rezervaci ${moto} v ${br} do ${DAYS(2)}. Chce prodloužit o 3 dny do ${DAYS(5)}. Zkontroluj dostupnost.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `Přepočítej cenu prodloužené rezervace — doplatek za 3 dny.`, agent: 'finance', tool: 'get_financial_overview' },
        { msg: `Potvrď doplatek za prodloužení.`, agent: 'bookings', tool: 'confirm_booking_payment' },
      ]
    },
  },
  {
    id: 'shorten_booking', name: 'Zkrácení + refund', icon: '⏪',
    agents: ['bookings','finance'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} ${ln} vrací ${moto} o 2 dny dříve. Uprav konec rezervace na dnes.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `Vypočítej refund za 2 nevyužité dny.`, agent: 'finance', tool: 'get_financial_overview' },
      ]
    },
  },
  {
    id: 'multi_extend_shorten', name: '3× prodloužení + zkrácení', icon: '📏',
    agents: ['bookings','finance','fleet'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO(), br = BRANCH()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} má rez. ${moto} v ${br} do ${DAYS(3)}. Prodlužuje o 1 den.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `${fn} znovu prodlužuje o 2 dny. Zkontroluj dostupnost.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `${fn} potřetí prodlužuje o 1 den. Je ${moto} volná?`, agent: 'fleet', tool: 'get_fleet_overview' },
        { msg: `Uprav rezervaci ${fn} na nový konec.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `${fn} nakonec vrací dříve — zkrať o 2 dny. Refund?`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `Kolik ${fn} celkem zaplatí po všech změnách?`, agent: 'finance', tool: 'get_financial_overview' },
      ]
    },
  },
  {
    id: 'pickup_change', name: 'Změna místa přistavení', icon: '📍',
    agents: ['bookings','fleet'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} má rez. ${moto} vyzvednutí Mezná. Chce změnit na Brno.`, agent: 'bookings', tool: 'update_booking_details' },
        { msg: `Ověř dostupnost ${moto} na pobočce Brno.`, agent: 'fleet', tool: 'get_fleet_overview' },
        { msg: `Potvrď změnu přistavení. Informuj zákazníka.`, agent: 'bookings', tool: 'update_booking_details' },
      ]
    },
  },
  {
    id: 'delivery_pickup', name: 'Přistavení zákazníkovi', icon: '🚚',
    agents: ['bookings','fleet'],
    generate: () => {
      const fn = NAME(), ln = SURNAME(), tag = TS(), moto = MOTO()
      return [
        { msg: `Vytvoř testovacího zákazníka ${fn} ${ln}, email test.sim.${tag}@motogo24.cz.`, agent: 'customers', tool: 'create_test_user' },
        { msg: `${fn} chce přistavení ${moto} na adresu Praha 2, Vinohradská 10. Zarezervuj s delivery.`, agent: 'bookings', tool: 'create_booking' },
        { msg: `Přiřaď řidiče pro přistavení. Kdo je dnes k dispozici?`, agent: 'fleet', tool: 'get_fleet_overview' },
        { msg: `Motorka přistavena. Aktualizuj stav na "picked_up".`, agent: 'bookings', tool: 'update_booking_status' },
      ]
    },
  },
]

// Import extra scenarios from part 2
import { SCENARIOS_EXTRA } from './aiTrainingScenariosExtra'

export const SCENARIOS = [...SCENARIOS_CORE, ...SCENARIOS_EXTRA]
export function getAllScenarios() { return SCENARIOS }
export function getScenarioById(id) { return SCENARIOS.find(s => s.id === id) }
