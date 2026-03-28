// ===== I18N.JS – Internationalization for MotoGo24 (part 1: cs, en, de, es) =====
// Supported: cs (default), en, de, es, fr, nl, pl

var _currentLang='cs';

var I18N={
cs:{
  nav:{home:'Domů',search:'Rezervovat',res:'Rezervace',shop:'Shop'},
  profile:{account:'Můj účet',settings:'Nastavení',help:'Pomoc & Podpora',other:'Ostatní',personalData:'Osobní údaje',docs:'Moje doklady',invoices:'Faktury a vyúčtování',contracts:'Dokumenty a smlouvy',payMethods:'Platební metody',notif:'Notifikace',biometric:'Biometrické přihlášení',privacy:'Soukromí & Oprávnění',language:'Jazyk aplikace',shareLocation:'Sdílení polohy',camera:'Fotoaparát',microphone:'Mikrofon',analytics:'Anonymní analytika',logout:'Odhlásit se',save:'Uložit',deleteAccount:'Smazat účet a všechna data'},
  // Doc module
  doc:{back:'Zpět',vopTitle:'Všeobecné obchodní podmínky',seat:'Sídlo',
    lessor:'Pronajímatel',lessee:'Nájemce',phone:'Telefon',
    contractTitle:'Smlouva o nájmu motocyklu',contractLabel:'Smlouva',
    contractSubject:'Předmět smlouvy',
    contractSubjectText:'Pronajímatel přenechává nájemci motocykl {moto} k dočasnému užívání od {from} do {to} ({days} dní).',
    contractPrice:'Cena nájmu',
    contractPriceText:'Celková cena nájmu činí {total} Kč. Cena je konečná, nejsme plátci DPH.',
    contractConditions:'Podmínky',
    contractConditionsText:'Nájemce je povinen vrátit motocykl ve stavu odpovídajícím běžnému opotřebení. Za škody způsobené porušením podmínek odpovídá nájemce v plné výši.',
    signNote:'Podepište prstem nebo myší',clearSign:'Smazat podpis',signBtn:'Podepsat ✓',
    signRequired:'Podpis',signFirst:'Nejdříve se podepište',signed:'Podepsáno',savedOK:'Dokument uložen',
    protocolTitle:'Předávací protokol',protocolLabel:'Předávací protokol',
    motorcycle:'Motocykl',pickupDate:'Datum vyzvednutí',returnDate:'Datum vrácení',
    protocolItems:'Předávané položky',protocolNotes:'Poznámky ke stavu',
    protocolNotesPlaceholder:'Poškrábání, závady, stav km...',
    invoiceAdvance:'Zálohová faktura',invoiceFinal:'Konečná faktura',
    supplier:'Dodavatel',customer:'Odběratel',issueDate:'Datum vystavení',
    dueDate:'Datum splatnosti',payMethod:'Způsob úhrady',card:'Platební karta',
    bankAccount:'Bankovní účet',item:'Položka',qty:'Množství',unitPrice:'Cena/den',
    total:'Celkem',rentalOf:'Pronájem motocyklu',days:'dní',extras:'Příslušenství',
    totalToPay:'Celkem k úhradě',sendEmail:'Odeslat e-mailem',downloadPDF:'Stáhnout PDF',
    emailSent:'Odesláno na',noInvoices:'Žádné faktury',shopInvoice:'Faktura – Shop',
    docsTitle:'Dokumenty a smlouvy',docsSubtitle:'Archiv smluvní dokumentace',
    gdprNote:'Přístupné pouze vám. Zpracování dle GDPR.',
    vopSubject:'Předmět',vopSubjectText:'Tyto VOP upravují podmínky pronájmu motocyklů provozovaného společností MotoGo24 s.r.o.',
    vopRental:'Pronájem',vopRentalText:'Minimální doba pronájmu je 1 den. Motocykl je předán s plnou nádrží a vrací se s plnou nádrží.',
    vopObligations:'Povinnosti nájemce',vopObligationsText:'Nájemce je povinen užívat motocykl v souladu s právními předpisy, pojistnými podmínkami a pokyny pronajímatele.',
    vopDeposit:'Kauce',vopDepositText:'Pronajímatel si vyhrazuje právo požadovat kauci ve výši až 30 000 Kč.',
    vopInsurance:'Pojištění',vopInsuranceText:'Motocykl je pojištěn povinným ručením a havarijním pojištěním se spoluúčastí nájemce.',
    vopCancel:'Storno podmínky',vopCancelText:'Více než 7 dní předem: plná refundace. 48h–7 dní: 50% vrácení. Do 48h: bez vrácení.',
    vopFinal:'Závěrečná ustanovení',vopFinalText:'Vztahy neupravené těmito VOP se řídí občanským zákoníkem č. 89/2012 Sb.'}
},
en:{
  nav:{home:'Home',search:'Book',res:'My bookings',shop:'Shop'},
  profile:{account:'My Account',settings:'Settings',help:'Help & Support',other:'Other',personalData:'Personal Data',docs:'My Documents',invoices:'Invoices',contracts:'Documents & Contracts',payMethods:'Payment Methods',notif:'Notifications',biometric:'Biometric Login',privacy:'Privacy & Permissions',language:'App Language',shareLocation:'Share Location',camera:'Camera',microphone:'Microphone',analytics:'Anonymous Analytics',logout:'Log Out',save:'Save',deleteAccount:'Delete account and all data'},
  doc:{back:'Back',vopTitle:'General Terms and Conditions',seat:'Registered office',
    lessor:'Lessor',lessee:'Lessee',phone:'Phone',
    contractTitle:'Motorcycle Rental Agreement',contractLabel:'Contract',
    contractSubject:'Subject',
    contractSubjectText:'The lessor provides the lessee with motorcycle {moto} for temporary use from {from} to {to} ({days} days).',
    contractPrice:'Rental price',
    contractPriceText:'The total rental price is {total} CZK. The price is final, we are not VAT payers.',
    contractConditions:'Conditions',
    contractConditionsText:'The lessee is obliged to return the motorcycle in a condition corresponding to normal wear. The lessee is fully liable for damages caused by breach of conditions.',
    signNote:'Sign with finger or mouse',clearSign:'Clear',signBtn:'Sign ✓',
    signRequired:'Signature',signFirst:'Please sign first',signed:'Signed',savedOK:'Document saved',
    protocolTitle:'Handover Protocol',protocolLabel:'Handover Protocol',
    motorcycle:'Motorcycle',pickupDate:'Pickup date',returnDate:'Return date',
    protocolItems:'Handover items',protocolNotes:'Condition notes',
    protocolNotesPlaceholder:'Scratches, defects, mileage...',
    invoiceAdvance:'Advance Invoice',invoiceFinal:'Final Invoice',
    supplier:'Supplier',customer:'Customer',issueDate:'Issue date',
    dueDate:'Due date',payMethod:'Payment method',card:'Credit card',
    bankAccount:'Bank account',item:'Item',qty:'Quantity',unitPrice:'Price/day',
    total:'Total',rentalOf:'Motorcycle rental',days:'days',extras:'Accessories',
    totalToPay:'Total to pay',sendEmail:'Send via email',downloadPDF:'Download PDF',
    emailSent:'Sent to',noInvoices:'No invoices',
    docsTitle:'Documents & Contracts',docsSubtitle:'Contract documentation archive',
    gdprNote:'Accessible only to you. GDPR compliant.',
    vopSubject:'Subject',vopSubjectText:'These GTC govern motorcycle rental operated by MotoGo24 s.r.o.',
    vopRental:'Rental',vopRentalText:'Minimum rental period is 1 day. Motorcycle is handed over with a full tank and must be returned with a full tank.',
    vopObligations:'Lessee obligations',vopObligationsText:'The lessee shall use the motorcycle in accordance with legal regulations, insurance terms and lessor instructions.',
    vopDeposit:'Deposit',vopDepositText:'The lessor reserves the right to require a deposit of up to 30,000 CZK.',
    vopInsurance:'Insurance',vopInsuranceText:'The motorcycle is covered by liability and collision insurance with lessee deductible.',
    vopCancel:'Cancellation policy',vopCancelText:'More than 7 days: full refund. 48h–7 days: 50% refund. Under 48h: no refund.',
    vopFinal:'Final provisions',vopFinalText:'Relations not governed by these GTC are governed by the Czech Civil Code No. 89/2012 Coll.'}
},
de:{
  nav:{home:'Start',search:'Buchen',res:'Buchungen',shop:'Shop'},
  profile:{account:'Mein Konto',settings:'Einstellungen',help:'Hilfe & Support',other:'Sonstiges',personalData:'Persönliche Daten',docs:'Meine Dokumente',invoices:'Rechnungen',contracts:'Dokumente & Verträge',payMethods:'Zahlungsmethoden',notif:'Benachrichtigungen',biometric:'Biometrische Anmeldung',privacy:'Datenschutz & Berechtigungen',language:'App-Sprache',shareLocation:'Standort teilen',camera:'Kamera',microphone:'Mikrofon',analytics:'Anonyme Analytik',logout:'Abmelden',save:'Speichern',deleteAccount:'Konto und alle Daten löschen'},
  doc:{back:'Zurück',vopTitle:'Allgemeine Geschäftsbedingungen',seat:'Sitz',
    lessor:'Vermieter',lessee:'Mieter',phone:'Telefon',
    contractTitle:'Motorrad-Mietvertrag',contractLabel:'Vertrag',
    contractSubject:'Gegenstand',
    contractSubjectText:'Der Vermieter überlässt dem Mieter das Motorrad {moto} zur vorübergehenden Nutzung vom {from} bis {to} ({days} Tage).',
    contractPrice:'Mietpreis',
    contractPriceText:'Der Gesamtmietpreis beträgt {total} CZK. Der Preis ist endgültig, kein MwSt.-Zahler.',
    contractConditions:'Bedingungen',
    contractConditionsText:'Der Mieter ist verpflichtet, das Motorrad in einem dem normalen Verschleiß entsprechenden Zustand zurückzugeben.',
    signNote:'Mit Finger oder Maus unterschreiben',clearSign:'Löschen',signBtn:'Unterschreiben ✓',
    signRequired:'Unterschrift',signFirst:'Bitte zuerst unterschreiben',signed:'Unterschrieben',savedOK:'Dokument gespeichert',
    protocolTitle:'Übergabeprotokoll',protocolLabel:'Übergabeprotokoll',
    motorcycle:'Motorrad',pickupDate:'Abholdatum',returnDate:'Rückgabedatum',
    protocolItems:'Übergabegegenstände',protocolNotes:'Zustandsnotizen',
    protocolNotesPlaceholder:'Kratzer, Mängel, Kilometerstand...',
    invoiceAdvance:'Vorauszahlungsrechnung',invoiceFinal:'Schlussrechnung',
    supplier:'Lieferant',customer:'Kunde',issueDate:'Ausstellungsdatum',
    dueDate:'Fälligkeitsdatum',payMethod:'Zahlungsmethode',card:'Kreditkarte',
    bankAccount:'Bankkonto',item:'Position',qty:'Menge',unitPrice:'Preis/Tag',
    total:'Gesamt',rentalOf:'Motorradmiete',days:'Tage',extras:'Zubehör',
    totalToPay:'Gesamtbetrag',sendEmail:'Per E-Mail senden',downloadPDF:'PDF herunterladen',
    emailSent:'Gesendet an',noInvoices:'Keine Rechnungen',
    docsTitle:'Dokumente & Verträge',docsSubtitle:'Vertragsarchiv',
    gdprNote:'Nur für Sie zugänglich. DSGVO-konform.',
    vopSubject:'Gegenstand',vopSubjectText:'Diese AGB regeln die Motorradmiete der MotoGo24 s.r.o.',
    vopRental:'Miete',vopRentalText:'Mindestmietdauer ist 1 Tag. Motorrad wird vollgetankt übergeben und vollgetankt zurückgegeben.',
    vopObligations:'Pflichten des Mieters',vopObligationsText:'Der Mieter muss das Motorrad gemäß den gesetzlichen Vorschriften und Versicherungsbedingungen nutzen.',
    vopDeposit:'Kaution',vopDepositText:'Der Vermieter behält sich das Recht vor, eine Kaution von bis zu 30.000 CZK zu verlangen.',
    vopInsurance:'Versicherung',vopInsuranceText:'Das Motorrad ist haftpflicht- und kaskoversichert mit Selbstbeteiligung des Mieters.',
    vopCancel:'Stornobedingungen',vopCancelText:'Mehr als 7 Tage: volle Erstattung. 48h–7 Tage: 50%. Unter 48h: keine Erstattung.',
    vopFinal:'Schlussbestimmungen',vopFinalText:'Nicht geregelte Beziehungen unterliegen dem tschechischen BGB Nr. 89/2012.'}
},
es:{
  nav:{home:'Inicio',search:'Reservar',res:'Reservas',shop:'Tienda'},
  profile:{account:'Mi Cuenta',settings:'Ajustes',help:'Ayuda',other:'Otros',personalData:'Datos Personales',docs:'Mis Documentos',invoices:'Facturas',contracts:'Documentos y Contratos',payMethods:'Métodos de Pago',notif:'Notificaciones',biometric:'Acceso Biométrico',privacy:'Privacidad y Permisos',language:'Idioma',shareLocation:'Compartir Ubicación',camera:'Cámara',microphone:'Micrófono',analytics:'Analítica Anónima',logout:'Cerrar Sesión',save:'Guardar',deleteAccount:'Eliminar cuenta y todos los datos'},
  doc:{back:'Atrás',vopTitle:'Condiciones Generales',seat:'Sede',
    lessor:'Arrendador',lessee:'Arrendatario',phone:'Teléfono',
    contractTitle:'Contrato de Alquiler de Motocicleta',contractLabel:'Contrato',
    contractSubject:'Objeto',
    contractSubjectText:'El arrendador cede al arrendatario la motocicleta {moto} para uso temporal del {from} al {to} ({days} días).',
    contractPrice:'Precio del alquiler',
    contractPriceText:'El precio total es {total} CZK. Precio final, no somos contribuyentes de IVA.',
    contractConditions:'Condiciones',
    contractConditionsText:'El arrendatario debe devolver la motocicleta en condiciones de desgaste normal.',
    signNote:'Firme con el dedo o ratón',clearSign:'Borrar',signBtn:'Firmar ✓',
    signRequired:'Firma',signFirst:'Firme primero',signed:'Firmado',savedOK:'Documento guardado',
    protocolTitle:'Protocolo de Entrega',protocolLabel:'Protocolo de Entrega',
    motorcycle:'Motocicleta',pickupDate:'Fecha de recogida',returnDate:'Fecha de devolución',
    protocolItems:'Artículos entregados',protocolNotes:'Notas de estado',
    protocolNotesPlaceholder:'Arañazos, defectos, kilometraje...',
    invoiceAdvance:'Factura Anticipada',invoiceFinal:'Factura Final',
    supplier:'Proveedor',customer:'Cliente',issueDate:'Fecha de emisión',
    dueDate:'Fecha de vencimiento',payMethod:'Método de pago',card:'Tarjeta',
    bankAccount:'Cuenta bancaria',item:'Artículo',qty:'Cantidad',unitPrice:'Precio/día',
    total:'Total',rentalOf:'Alquiler de motocicleta',days:'días',extras:'Accesorios',
    totalToPay:'Total a pagar',sendEmail:'Enviar por email',downloadPDF:'Descargar PDF',
    emailSent:'Enviado a',noInvoices:'Sin facturas',
    docsTitle:'Documentos y Contratos',docsSubtitle:'Archivo de documentación',
    gdprNote:'Accesible solo para usted. Conforme con RGPD.',
    vopSubject:'Objeto',vopSubjectText:'Estas condiciones regulan el alquiler de motocicletas de MotoGo24 s.r.o.',
    vopRental:'Alquiler',vopRentalText:'Período mínimo: 1 día. La moto se entrega y devuelve con tanque lleno.',
    vopObligations:'Obligaciones',vopObligationsText:'El arrendatario usará la motocicleta conforme a la ley y condiciones del seguro.',
    vopDeposit:'Depósito',vopDepositText:'El arrendador puede exigir un depósito de hasta 30.000 CZK.',
    vopInsurance:'Seguro',vopInsuranceText:'La moto tiene seguro de responsabilidad civil y a todo riesgo con franquicia.',
    vopCancel:'Cancelación',vopCancelText:'Más de 7 días: reembolso total. 48h–7 días: 50%. Menos de 48h: sin reembolso.',
    vopFinal:'Disposiciones finales',vopFinalText:'Relaciones no reguladas se rigen por el Código Civil checo nº 89/2012.'}
}
};

function _t(section){
  var lang=I18N[_currentLang]||I18N.cs;
  return lang[section]||I18N.cs[section]||{};
}

function setLanguage(lang){
  if(!I18N[lang]) return;
  _currentLang=lang;
  try{localStorage.setItem('mg_lang',lang);}catch(e){}
  // Update navigation labels
  var t=_t('nav');
  var labels=document.querySelectorAll('#bnav .ni span');
  if(labels.length>=4){
    labels[0].textContent=t.home;
    labels[1].textContent=t.search;
    labels[2].textContent=t.res;
    labels[3].textContent=t.shop;
  }
  // Update profile labels
  var p=_t('profile');
  if(p){
    var map={'prof-sec-account':'account','prof-sec-settings':'settings','prof-sec-help':'help','prof-sec-other':'other','prof-lbl-personal':'personalData','prof-lbl-docs':'docs','prof-lbl-invoices':'invoices','prof-lbl-contracts':'contracts','prof-lbl-pay':'payMethods','prof-lbl-notif':'notif','prof-lbl-bio':'biometric','prof-lbl-priv':'privacy','prof-lbl-lang':'language','prof-lbl-logout':'logout','prof-lbl-delete':'deleteAccount','prof-priv-loc':'shareLocation','prof-priv-cam':'camera','prof-priv-mic':'microphone','prof-priv-anal':'analytics'};
    for(var id in map){var el=document.getElementById(id);if(el&&p[map[id]])el.textContent=p[map[id]];}
  }
  // Re-render current screen if needed
  if(typeof cur!=='undefined'){
    if(cur==='s-contracts'&&typeof renderContractsPage==='function') renderContractsPage();
    if(cur==='s-invoices'&&typeof renderInvoicesPage==='function') renderInvoicesPage();
  }
  showT('🌐','OK',lang.toUpperCase());
}
