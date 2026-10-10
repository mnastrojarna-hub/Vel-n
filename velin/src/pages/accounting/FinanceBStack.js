// Velín mobil/tablet — sdílené třídy záložek Účetnictví (události, výjimky, majetek, závazky,
// dodavatelé), objednávek a výkazů. Vše jen pod 1024 px — desktop zůstává beze změny.

// Tablet (768–1023 px): karta řádku (<Table stack="tablet">) má buňky ve 2 sloupcích;
// poslední buňka (akce, rozbalený detail, prázdný stav) a buňky mg-stack-full zabírají oba.
// TAB2_GRID = jen mřížka (řádky s vlastním pozadím, např. žlutý výběr); TAB2 navíc bílé karty —
// řádky TRow mají inline průhledné pozadí (jinak by karta splývala s pozadím stránky).
export const TAB2_GRID = 'md:max-lg:[&>table>tbody>tr]:!grid md:max-lg:[&>table>tbody>tr]:grid-cols-2 md:max-lg:[&>table>tbody>tr]:gap-x-4 md:max-lg:[&>table>tbody>tr>td.mg-stack-full]:col-span-2 md:max-lg:[&>table>tbody>tr>td:last-child]:col-span-2'
export const TAB2 = TAB2_GRID + ' max-lg:[&>table>tbody>tr]:!bg-white'
// Tablet: zaškrtávátko (1. buňka) na vlastním řádku karty → hlavní údaj (název/číslo) začíná vlevo nahoře
export const CB_ROW = 'md:max-lg:[&>table>tbody>tr>td:first-child]:col-span-2'

// Dotyk: tlačítka v buňkách tabulky aspoň 36 px vysoká, popisek se nezalamuje uprostřed slova (mobil/tablet)
export const TOUCH_BTNS = 'max-lg:[&_td_button]:min-h-[36px] max-lg:[&_td_button]:whitespace-nowrap'

// Telefon: bílá obalová Card průhledná, aby řádky tabulky byly samostatné karty
export const CARD_PHONE = 'max-md:!bg-transparent max-md:!shadow-none max-md:!p-0'

// Telefon (< 768 px, <Table stack>): bílé karty řádků TRow
export const ROWS_WHITE = 'max-md:[&>table>tbody>tr]:!bg-white'
