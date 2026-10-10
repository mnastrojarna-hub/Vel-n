// Zaškrtávátka v tabulkách Dokumentů s <Table stack="tablet"> (Vygenerované, Zaslané emaily).
// PC (≥ 1024 px): obyčejný inline <label> kolem checkboxu → vzhled beze změny.
// < 1024 px (karty): „vybrat vše“ je čip nad kartami → dostane popisek; řádkový checkbox
// má klepací plochu 40 px. Řádkovou buňku vykreslit jako <TD label=""> (jinak by
// stackTables převzal popisek „Vybrat vše“ ze záhlaví).

export function DocCheckAll({ children }) {
  return (
    <label className="max-lg:inline-flex max-lg:items-center max-lg:gap-2 max-lg:cursor-pointer">
      {children}
      <span className="text-xs lg:hidden">Vybrat vše</span>
    </label>
  )
}

export function DocCheckRow({ children }) {
  return (
    <label className="max-lg:inline-flex max-lg:items-center max-lg:min-w-[40px] max-lg:min-h-[40px] max-lg:cursor-pointer">
      {children}
    </label>
  )
}
