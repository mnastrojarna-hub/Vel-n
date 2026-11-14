import '../../../core/i18n/i18n_provider.dart';
import '../../home/v2/funnel_dates.dart';
import '../moto_model.dart';

/// Availability of a bike when no dates are given (list card, detail hero;
/// the Home offer card says the same): "Volná dnes" (`availableToday`,
/// [today] = true → the live dot), else "Volná od 19. 11." from the read-
/// only `homeNextFreeProvider` (`get_motos_availability_status`), else none.
(String?, bool today) bikeFreeLabel(AppTranslations tr, Motorcycle m, Map<String, DateTime> nextFree, {DateTime? now}) {
  if (m.availableToday == true) return (tr.tr('v2CatFreeToday'), true);
  final next = nextFree[m.id];
  final n = now ?? DateTime.now();
  if (next == null || !next.isAfter(DateTime(n.year, n.month, n.day))) return (null, false);
  return (tr.trArgs('homeOfferFreeFrom', {'date': funnelDate(tr, next)}), false);
}
