// Velín mobil/tablet — sdílené třídy záložek Finance (přehled, faktury, dobropisy, dodací listy,
// smlouvy, přijaté faktury, platby, pokladna). Vše jen pod 1024 px — desktop zůstává beze změny.

// Tablet (768–1023 px): karta řádku (<Table stack="tablet">) má popisky ve 2 sloupcích (telefon 1 sloupec).
export const TAB_ROW = 'md:max-lg:!grid md:max-lg:grid-cols-2 md:max-lg:gap-x-4'

// Řádky TRow mají inline průhledné pozadí → karta řádku dostane bílé (jinak splývá s pozadím stránky).
// Jen telefon (<Table stack>); className tabulky (obal). Pro stack="tablet" se místo TRow použije <tr> bez inline pozadí.
export const ROWS_WHITE = 'max-md:[&>table>tbody>tr]:!bg-white'

// Bílá obalová Card průhledná, aby řádky tabulky byly samostatné karty (telefon / telefon + tablet).
export const STACK_CARD = 'max-md:!bg-transparent max-md:!shadow-none max-md:!p-0'
export const STACK_CARD_TAB = 'max-lg:!bg-transparent max-lg:!shadow-none max-lg:!p-0'
