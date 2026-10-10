import { SelectAllCheckbox, RowCheckbox } from '../../components/ui/BulkActionsBar'

// E-shop tabulky s <Table stack> (Objednávky, Nákupy, Dodavatelé) — zaškrtávátka pro dotyk.
// PC (≥ 1024 px): label je obyčejný inline obal kolem checkboxu → vzhled beze změny.
// Tablet: klepací plocha 36 px, telefon (karty): 40 px — klepnutí vedle checkboxu tak
// neotevře omylem detail řádku. Řádkovou buňku vždy vykreslit jako <TD label=""> (bez popisku).

export function StackSelectAll(props) {
  return (
    <label className="max-lg:inline-flex max-lg:items-center max-lg:gap-2 max-lg:min-w-[36px] max-lg:min-h-[36px] max-md:min-h-[28px] max-lg:cursor-pointer">
      <SelectAllCheckbox {...props} />
      {/* text jen v kartovém zobrazení (telefon) — čip „vybrat vše“ nad kartami */}
      <span className="text-sm md:hidden">Vybrat vše</span>
    </label>
  )
}

export function StackRowCheck(props) {
  return (
    <label onClick={e => e.stopPropagation()}
      className="max-lg:inline-flex max-lg:items-center max-lg:min-w-[36px] max-lg:min-h-[36px] max-md:min-w-[40px] max-md:min-h-[40px] max-lg:cursor-pointer">
      <RowCheckbox {...props} />
    </label>
  )
}
