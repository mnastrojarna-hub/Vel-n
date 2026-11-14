// The Velín banner (`app_settings.header_banner`) exactly as it is live on
// 2026-11-14 (read from the live table): enabled, the Czech winter text,
// bg #1a2e22 (almost the colour of the dark v2 header), text #74FB71 and
// the 7 fresh translations (`translations_src` = SHA-1 of the Czech text,
// so `BannerData.forLang` uses them, as the app does).
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';

const kLiveBannerText = 'V zimním období od 1.11.2026 do 25.3.2027 je motopůjčovna zavřená. '
    'Jsme vám ale k dispozici na telefonu nebo e-mailu. Dárkové poukazy odesíláme!';

const kLiveBanner = BannerData(
  enabled: true,
  text: kLiveBannerText,
  bg: Color(0xFF1A2E22),
  color: Color(0xFF74FB71),
  translations: {
    'de': 'In der Wintersaison vom 1.11.2026 bis 25.3.2027 ist die Motorradverleihstation geschlossen. '
        'Wir stehen Ihnen aber telefonisch oder per E-Mail zur Verfügung. Wir versenden Geschenkgutscheine!',
    'en': 'During the winter season from 1.11.2026 to 25.3.2027, the motorcycle rental is closed. '
        'However, we are available to you by phone or email. We send gift vouchers!',
    'es': 'Durante el período invernal del 1.11.2026 al 25.3.2027, el alquiler de motocicletas está cerrado. '
        'Sin embargo, estamos disponibles para usted por teléfono o correo electrónico. ¡Enviamos vales de regalo!',
    'fr': 'Pendant la période hivernale du 1.11.2026 au 25.3.2027, la moto-location est fermée. '
        'Nous restons à votre disposition par téléphone ou par e-mail. Nous envoyons des bons cadeaux !',
    'nl': 'In de winterperiode van 1.11.2026 tot 25.3.2027 is de motorfietsverhuurbedrijf gesloten. '
        'Wij zijn echter beschikbaar via telefoon of e-mail. Wij versturen cadeaubonnen!',
    'pl': 'W okresie zimowym od 1.11.2026 do 25.3.2027 wypożyczalnia motocykli jest zamknięta. '
        'Jesteśmy jednak dostępni telefonicznie lub e-mailowo. Wysyłamy bony podarunkowe!',
    'uk': 'У зимовий період з 1.11.2026 по 25.3.2027 мотопрокат закритий. '
        'Але ми доступні для вас по телефону або електронній пошті. Ми відправляємо подарункові ваучери!',
  },
);

/// `bannerProvider` → the live banner in the app's language (as the real
/// provider: fresh translation, else Czech); [on] false = no banner row.
Override liveBannerOverride({bool on = true}) => bannerProvider.overrideWith(
    (ref) => AsyncData(on ? kLiveBanner.forLang(ref.watch(localeProvider).languageCode) : null));
