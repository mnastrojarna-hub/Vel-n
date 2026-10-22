// ===== _shared/paid-change-customer-mail-why.ts =====
// Důvody nezapsané zaplacené změny v e-mailu zákazníkovi (8 jazyků; f1 2026-10-22) — stejný
// význam jako web (editRez.paid.why.*) a appka (pdFailStatus / pdFailDate / pdFailLicense), rejstřík
// jako ostatní texty e-mailu (paid-change-customer-mail-texts.ts). Bez kontaktů (D5).
//  closed  — rezervace mezitím skončila / byla zrušená: BEZ věty „platí beze změny" a bez „zkuste znovu",
//  date    — den výměny mezitím uplynul,
//  license — chybí řidičské oprávnění na vybranou motorku.
import type { Lang } from './paid-change-customer-mail-texts.ts'

export type Why = { whyClosed: string; whyDate: string; whyLicense: string; ctaList: string }

// {num} = číslo rezervace
export const WHY: Record<Lang, Why> = {
  cs: { whyClosed: 'zaplacenou změnu vaší rezervace č. {num} nešlo zapsat, protože rezervace mezitím skončila nebo byla zrušená.',
    whyDate: 'zaplacenou změnu nešlo zapsat, protože zvolený den výměny mezitím uplynul.',
    whyLicense: 'zaplacenou změnu nešlo zapsat, protože na vybranou motorku nemáte potřebné řidičské oprávnění.', ctaList: 'Moje rezervace' },
  en: { whyClosed: 'the paid change to your booking #{num} could not be saved because the booking has ended or been cancelled in the meantime.',
    whyDate: 'the paid change could not be saved because the chosen swap day has passed in the meantime.',
    whyLicense: 'the paid change could not be saved because you do not have the driving licence category required for the chosen motorcycle.', ctaList: 'My bookings' },
  de: { whyClosed: 'die bezahlte Änderung Ihrer Buchung Nr. {num} konnte nicht gespeichert werden, weil die Buchung inzwischen beendet oder storniert wurde.',
    whyDate: 'die bezahlte Änderung konnte nicht gespeichert werden, weil der gewählte Tauschtag inzwischen verstrichen ist.',
    whyLicense: 'die bezahlte Änderung konnte nicht gespeichert werden, weil Sie für das gewählte Motorrad nicht die erforderliche Führerscheinklasse haben.', ctaList: 'Meine Buchungen' },
  nl: { whyClosed: 'de betaalde wijziging van je boeking nr. {num} kon niet worden opgeslagen, omdat de boeking intussen is afgelopen of geannuleerd.',
    whyDate: 'de betaalde wijziging kon niet worden opgeslagen, omdat de gekozen wisseldag intussen voorbij is.',
    whyLicense: 'de betaalde wijziging kon niet worden opgeslagen, omdat je niet het vereiste rijbewijs hebt voor de gekozen motor.', ctaList: 'Mijn boekingen' },
  es: { whyClosed: 'no se pudo guardar el cambio pagado de tu reserva n.º {num} porque la reserva ha finalizado o se ha cancelado entretanto.',
    whyDate: 'no se pudo guardar el cambio pagado porque el día de cambio elegido ya ha pasado.',
    whyLicense: 'no se pudo guardar el cambio pagado porque no tienes el permiso de conducir necesario para la moto elegida.', ctaList: 'Mis reservas' },
  fr: { whyClosed: 'la modification payée de votre réservation n° {num} n’a pas pu être enregistrée, car la réservation s’est terminée ou a été annulée entre-temps.',
    whyDate: 'la modification payée n’a pas pu être enregistrée, car le jour d’échange choisi est passé entre-temps.',
    whyLicense: 'la modification payée n’a pas pu être enregistrée, car vous n’avez pas la catégorie de permis requise pour la moto choisie.', ctaList: 'Mes réservations' },
  pl: { whyClosed: 'opłaconej zmiany Twojej rezerwacji nr {num} nie udało się zapisać, ponieważ rezerwacja w międzyczasie się zakończyła lub została anulowana.',
    whyDate: 'opłaconej zmiany nie udało się zapisać, ponieważ wybrany dzień wymiany już minął.',
    whyLicense: 'opłaconej zmiany nie udało się zapisać, ponieważ nie masz wymaganej kategorii prawa jazdy na wybrany motocykl.', ctaList: 'Moje rezerwacje' },
  uk: { whyClosed: 'оплачену зміну вашого бронювання № {num} не вдалося зберегти, бо бронювання тим часом завершилося або було скасоване.',
    whyDate: 'оплачену зміну не вдалося зберегти, бо обраний день заміни вже минув.',
    whyLicense: 'оплачену зміну не вдалося зберегти, бо у вас немає потрібної категорії водійського посвідчення для обраного мотоцикла.', ctaList: 'Мої бронювання' },
}
