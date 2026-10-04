import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../auth/widgets/toast_helper.dart';
import '../booking_gate_provider.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart';
import 'res_detail_card.dart';
import 'res_detail_row.dart';

/// Karta „Přístupové kódy“ v detailu rezervace (po celý termín — i PŘED
/// vydáním motorky). Pořadí = pořadí zadávání na pobočce: kód schránky
/// s klíčem od brány (jen pobočka s bránou, až po vydání kódu motorky) →
/// kód šatny → kód motorky. Bez brány vypadá karta jako dřív.
/// Důvod zadržení kódu motorky při výměně motorky (withhold_swap_next_codes).
const swapWithheldReason = 'Vraťte nejdřív původní motorku';

class ResAccessCodesCard extends ConsumerWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  const ResAccessCodesCard({super.key, required this.res, required this.doorCodesAsync});

  /// Try to release withheld door codes. If documents are already uploaded the
  /// backend RPC releases them immediately; otherwise we route the customer to
  /// the documents screen to scan OP/ŘP, then retry the release on return.
  Future<void> _handleReleaseCodes(BuildContext context, WidgetRef ref) async {
    var err = await releaseDoorCodes(res.id);
    if (err == null) {
      if (!context.mounted) return;
      ref.invalidate(doorCodesProvider(res.id));
      showMotoGoToast(context, icon: '🔑', title: t(context).tr('success'), message: t(context).tr('codesReleased'));
      return;
    }
    // Nemá doklady → nech zákazníka nahrát fotky, pak zkus uvolnit znovu.
    if (!context.mounted) return;
    await context.push(Routes.docs);
    if (!context.mounted) return;
    err = await releaseDoorCodes(res.id);
    if (!context.mounted) return;
    ref.invalidate(doorCodesProvider(res.id));
    if (err == null) {
      showMotoGoToast(context, icon: '🔑', title: t(context).tr('success'), message: t(context).tr('codesReleased'));
    } else {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('error'), message: t(context).tr('codesStillWithheld'));
    }
  }

  Widget _title(BuildContext context, {Widget? trailing}) => Row(children: [
        const Text('🔑', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(t(context).tr('accessCodes'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `st` je do podpisu protokolu „Nadcházející“, kódy ale zákazník
    // potřebuje právě v den vyzvednutí → kalendářní `inRentalTerm`.
    return doorCodesAsync.when(
      data: (codes) {
        if (codes.isEmpty || !res.inRentalTerm) return const SizedBox.shrink();
        final gate = ref.watch(bookingGateInfoProvider(res.id)).valueOrNull ?? BookingGateInfo.none;
        // Kód držený výměnou motorky uvolní až vrácení původní motorky — tlačítko
        // „nahrát doklady“ by tu nepomohlo (RPC ho odmítne).
        final hasWithheld = codes.any((c) => !c.sentToCustomer && c.withheldReason != swapWithheldReason);
        // Pořadí zadávání u pobočky s bránou: (brána →) šatna → motorka — jako zpráva,
        // SMS i e-mail. Bez brány (Mezná) beze změny = pořadí z DB jako dosud.
        final locker = codes.where((c) => c.codeType == 'accessories');
        final moto = codes.where((c) => c.codeType == 'motorcycle');
        final other = codes.where((c) => c.codeType != 'accessories' && c.codeType != 'motorcycle');
        final sorted = gate.hasGate ? [...locker, ...moto, ...other] : codes;
        final lockerLabel = gate.lockerDoor != null
            ? t(context).tr('lockerCodeDoor').replaceAll('{n}', '${gate.lockerDoor}')
            : t(context).tr('lockerCode');
        return Column(
          children: [
            ResDetailCard(children: [
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _title(context)),
              // 1) Brána — kód schránky s klíčem (jen když ho server vydal).
              if (gate.gateCode != null) ...[
                ResDetailRow(label: t(context).tr('gateCodeLabel'), value: gate.gateCode, bold: true),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(t(context).tr('gateCodeHint'),
                      style: const TextStyle(fontSize: 11, height: 1.35, fontWeight: FontWeight.w600, color: MotoGoColors.g500)),
                ),
              ],
              // „Kód šatny“ (accessories) / „Kód motorky“ (motorcycle).
              // Kód motorky kiosk pustí až po podepsaném předávacím
              // protokolu → poznámka pod VYDANÝM kódem samoobslužné
              // pobočky, dokud podpis chybí (zadržený kód / obslužná
              // pobočka protokol v appce neřeší).
              ...sorted.map((c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ResDetailRow(
                      label: c.codeType == 'motorcycle' ? t(context).tr('motoCode') : lockerLabel,
                      value: c.sentToCustomer ? c.doorCode : (c.withheldReason ?? t(context).tr('awaitingDocs')),
                      bold: c.sentToCustomer,
                    ),
                    if (c.codeType == 'motorcycle' && c.sentToCustomer && res.isSelfService && !res.protocolSigned)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          onTap: () => context.push(Routes.protocol, extra: res),
                          child: Text('📝 ${t(context).tr('protocolFirst')}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.amber)),
                        ),
                      ),
                  ])),
              // Vlastní výbava bez nároku na šatnu — žádný kód šatny nechybí
              // (i odvozeně u starších rezervací bez own_gear, viz model).
              if (res.ownGearEffective && !codes.any((c) => c.codeType == 'accessories'))
                ResDetailRow(label: t(context).tr('lockerCode'), value: t(context).tr('ownGearNoLocker')),
              // Kódy zadržené (chybí doklady) → CTA: zkus uvolnit (pokud už
              // jsou doklady nahrané), jinak naviguj na nahrání dokladů.
              if (hasWithheld) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleReleaseCodes(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.green,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: Text(t(context).tr('uploadDocsForCodes')),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
          ],
        );
      },
      loading: () => res.inRentalTerm
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ResDetailCard(children: [
                _title(context,
                    trailing: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green))),
              ]),
            )
          : const SizedBox.shrink(),
      error: (_, __) => res.inRentalTerm
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ResDetailCard(children: [
                Row(children: [
                  const Text('🔑', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(t(context).tr('doorCodesUnavailable'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400))),
                ]),
              ]),
            )
          : const SizedBox.shrink(),
    );
  }
}
