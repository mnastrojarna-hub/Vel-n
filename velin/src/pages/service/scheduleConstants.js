// Schedule types for planned services and inspections
export const SCHEDULE_TYPES = [
  { value: 'single_service', label: 'Jednorázový servis', icon: '🔧', desc: 'Naplánovat servis jedné motorky na konkrétní den' },
  { value: 'inspection_moto', label: 'Inspekce motorky', icon: '🔍', desc: 'Zevrubná kontrola jedné nebo více motorek — neblokuje rezervace' },
  { value: 'inspection_branch', label: 'Kontrola pobočky', icon: '🏢', desc: 'Autonomní zevrubná kontrola celé pobočky — neblokuje rezervace' },
  { value: 'recurring', label: 'Pravidelný servis', icon: '🔄', desc: 'Opakovaný plán: každých X dní, po X rezervacích apod.' },
]

export const RECURRING_INTERVALS = [
  { value: 'days', label: 'Každých X dní', placeholder: '14' },
  { value: 'reservations', label: 'Po každých X rezervacích', placeholder: '4' },
  { value: 'km', label: 'Po každých X km', placeholder: '1000' },
  { value: 'monthly', label: 'Každý měsíc (pevný den)', placeholder: '1' },
]

export const INSPECTION_ITEMS = [
  { id: 'visual', label: 'Vizuální stav motorky' },
  { id: 'tires', label: 'Stav pneumatik' },
  { id: 'brakes', label: 'Brzdy (vizuálně)' },
  { id: 'chain', label: 'Řetěz — napnutí, mazání' },
  { id: 'lights', label: 'Světla a blinkry' },
  { id: 'fluids', label: 'Hladiny kapalin' },
  { id: 'cleanliness', label: 'Čistota motorky' },
  { id: 'damage', label: 'Poškození / škrábance' },
  { id: 'documents', label: 'Doklady (TP, pojistka)' },
  { id: 'accessories', label: 'Příslušenství (helma, zámek)' },
  { id: 'station', label: 'Stav stanoviště / boxu' },
  { id: 'signage', label: 'Označení pobočky, navigace' },
]

export const WEEKDAYS = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne']
