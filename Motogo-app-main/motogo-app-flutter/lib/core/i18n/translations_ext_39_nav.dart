/// Navigace zpět (požadavek majitele 2026-10-16: z každé obrazovky jde
/// odejít zpět, nic se neztratí potichu). Klíče `nav*` — potvrzení před
/// zahozením úprav trasy a poctivý výsledek skenu dokladů bez odpovědi
/// serveru. Tyká se ve všech jazycích.
const Map<String, Map<String, String>> translationsExt39Nav = {
  'cs': {
    'navDiscardRouteTitle': 'Zahodit úpravy trasy?',
    'navDiscardRouteBody': 'Přidané, odebrané ani přeházené zastávky se neuloží. Chceš-li si trasu nechat, ulož ji nejdřív do Mých tras.',
    'navDocsVerifyPending': 'Fotky dokladů máme, ale ověření se teď nepodařilo dokončit (nejspíš slabý signál). Stav – a případně co ještě chybí – uvidíš v Mých dokladech.',
  },
  'en': {
    'navDiscardRouteTitle': 'Discard your route changes?',
    'navDiscardRouteBody': "Stops you added, removed or reordered won't be saved. To keep the route, save it to My Routes first.",
    'navDocsVerifyPending': "We have your document photos, but the check couldn't finish right now (probably a weak signal). You'll see the status – and anything still missing – in My documents.",
  },
  'de': {
    'navDiscardRouteTitle': 'Änderungen an der Route verwerfen?',
    'navDiscardRouteBody': 'Hinzugefügte, entfernte oder umsortierte Stopps werden nicht gespeichert. Wenn du die Route behalten willst, speichere sie zuerst in Meine Routen.',
    'navDocsVerifyPending': 'Die Fotos deiner Dokumente haben wir, aber die Prüfung konnte gerade nicht abgeschlossen werden (wahrscheinlich schwaches Signal). Den Stand – und was eventuell noch fehlt – siehst du unter Meine Dokumente.',
  },
  'es': {
    'navDiscardRouteTitle': '¿Descartar los cambios de la ruta?',
    'navDiscardRouteBody': 'Las paradas que has añadido, quitado o reordenado no se guardarán. Si quieres conservar la ruta, guárdala primero en Mis rutas.',
    'navDocsVerifyPending': 'Ya tenemos las fotos de tus documentos, pero la verificación no se ha podido completar ahora (probablemente por mala señal). El estado – y lo que aún falte – lo verás en Mis documentos.',
  },
  'fr': {
    'navDiscardRouteTitle': "Abandonner les modifications de l'itinéraire ?",
    'navDiscardRouteBody': "Les étapes ajoutées, supprimées ou réordonnées ne seront pas enregistrées. Pour garder l'itinéraire, enregistre-le d'abord dans Mes itinéraires.",
    'navDocsVerifyPending': "Nous avons bien les photos de tes documents, mais la vérification n'a pas pu se terminer pour l'instant (probablement un signal faible). Tu verras l'état – et ce qui manque encore – dans Mes documents.",
  },
  'nl': {
    'navDiscardRouteTitle': 'Wijzigingen aan de route weggooien?',
    'navDiscardRouteBody': 'Toegevoegde, verwijderde of verplaatste stops worden niet opgeslagen. Wil je de route bewaren, sla hem dan eerst op in Mijn routes.',
    'navDocsVerifyPending': "We hebben de foto's van je documenten, maar de controle kon nu niet worden afgerond (waarschijnlijk zwak signaal). De status – en wat eventueel nog ontbreekt – zie je bij Mijn documenten.",
  },
  'pl': {
    'navDiscardRouteTitle': 'Odrzucić zmiany trasy?',
    'navDiscardRouteBody': 'Dodane, usunięte ani przestawione przystanki nie zostaną zapisane. Jeśli chcesz zachować trasę, najpierw zapisz ją w Moich trasach.',
    'navDocsVerifyPending': 'Zdjęcia dokumentów mamy, ale weryfikacji nie udało się teraz dokończyć (pewnie słaby zasięg). Stan – i ewentualne braki – zobaczysz w Moich dokumentach.',
  },
  'uk': {
    'navDiscardRouteTitle': 'Скасувати зміни маршруту?',
    'navDiscardRouteBody': 'Додані, видалені чи переставлені зупинки не збережуться. Щоб зберегти маршрут, спершу збережи його в «Мої маршрути».',
    'navDocsVerifyPending': 'Фото документів ми отримали, але перевірку зараз не вдалося завершити (ймовірно, слабкий сигнал). Стан – і що, можливо, ще бракує – побачиш у розділі «Мої документи».',
  },
};
