
import '../../../core/i18n/i18n_provider.dart';

/// What the customer wants to change (V22 edit chooser "Co chceš změnit?").
/// extend / shorten / move / swap = today's four tabs; time / place / moto
/// / gear = the sections today's extend tab shows on one page.
enum ResEditIntent { extend, shorten, move, swap, time, place, moto, gear }

String resEditIntentTitle(AppTranslations tr, ResEditIntent i) => switch (i) {
      ResEditIntent.extend => tr.tr('v2ResIntExtend'),
      ResEditIntent.shorten => tr.tr('v2ResIntShorten'),
      ResEditIntent.move => tr.tr('moveChangePlace'),
      ResEditIntent.swap => tr.tr('swap.tab'),
      ResEditIntent.time => tr.tr('v2ResIntTime'),
      ResEditIntent.place => tr.tr('v2ResIntPlace'),
      ResEditIntent.moto => tr.tr('v2ResIntMoto'),
      ResEditIntent.gear => tr.tr('v2ResIntGear'),
    };
