import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import '../booking/booking_provider.dart';
import '../catalog/catalog_provider.dart';
import '../reservations/reservation_provider.dart';
import 'payment_provider.dart';

/// Stav dokladů na děkovací stránce — parita s webovou `/potvrzeni`:
/// - `verified` = doklady OK (nebo dětská motorka, kde se nevyžadují) → zelený badge
/// - `missing` = chybí / propadlý ŘP / chybí OP → oranžový badge + návod jak doplnit
/// - `unknown` = ještě nestihli jsme se ptát backendu (loading)
enum _DocsStatus { unknown, verified, missing }

class _ConfirmInfo {
  final _DocsStatus docsStatus;
  final String? missingReason; // text z check_booking_docs_status (pokud missing)
  final bool isChildBike; // license_required = 'N' → bez dokladů a bez výbavy
  const _ConfirmInfo({
    required this.docsStatus,
    required this.missingReason,
    required this.isChildBike,
  });
}

/// Payment success / confirmation screen — mirrors s-success from templates-done.js.
/// Shows animated checkmark, booking details, docs status (✓ Ověřeny / ⚠ Neověřeny)
/// and skipuje docs sekci pro dětské motorky (license_required='N').
class PaymentConfirmationScreen extends ConsumerStatefulWidget {
  const PaymentConfirmationScreen({super.key});

  @override
  ConsumerState<PaymentConfirmationScreen> createState() =>
      _PaymentConfirmationScreenState();
}

class _PaymentConfirmationScreenState
    extends ConsumerState<PaymentConfirmationScreen> {
  _ConfirmInfo _info = const _ConfirmInfo(
    docsStatus: _DocsStatus.unknown,
    missingReason: null,
    isChildBike: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfirmInfo());
  }

  Future<void> _loadConfirmInfo() async {
    final bookingId = ref.read(lastConfirmedBookingProvider);
    if (bookingId == null) {
      // Fallback: rezervace přišla z jiné cesty (např. extension); použij draft
      // z booking flow, ale moto neumíme — bez bookingId nemůžeme zjistit doklady.
      final moto = ref.read(bookingMotoProvider);
      final isChild = (moto?.licenseRequired ?? '').toUpperCase() == 'N';
      if (!mounted) return;
      setState(() {
        _info = _ConfirmInfo(
          docsStatus: isChild ? _DocsStatus.verified : _DocsStatus.unknown,
          missingReason: null,
          isChildBike: isChild,
        );
      });
      return;
    }

    try {
      // 1) Nacti booking + moto.license_required jedním selectem (RLS dovolí
      //    vlastníkovi přes bookings_user_select policy).
      final res = await MotoGoSupabase.client
          .from('bookings')
          .select('id, user_id, moto_id, end_date, motorcycles!moto_id(license_required)')
          .eq('id', bookingId)
          .maybeSingle();

      if (res == null) {
        if (!mounted) return;
        setState(() => _info = const _ConfirmInfo(
              docsStatus: _DocsStatus.unknown,
              missingReason: null,
              isChildBike: false,
            ));
        return;
      }

      final moto = res['motorcycles'] as Map<String, dynamic>?;
      final license = (moto?['license_required'] as String?)?.toUpperCase() ?? '';
      final isChild = license == 'N';

      // 2) Dětská motorka — nevyžaduje doklady; auto-verified bez RPC.
      if (isChild) {
        if (!mounted) return;
        setState(() => _info = const _ConfirmInfo(
              docsStatus: _DocsStatus.verified,
              missingReason: null,
              isChildBike: true,
            ));
        return;
      }

      // 3) RPC check_booking_docs_status: NULL = doklady OK,
      //    neprázdný string = withheld_reason (chybí / propadlý ŘP / OP).
      final docsRes = await MotoGoSupabase.client.rpc(
        'check_booking_docs_status',
        params: {
          'p_user_id': res['user_id'],
          'p_end_date': res['end_date'],
          'p_moto_id': res['moto_id'],
        },
      );
      final docsReason = (docsRes is String && docsRes.trim().isNotEmpty)
          ? docsRes.trim()
          : null;
      if (!mounted) return;
      setState(() => _info = _ConfirmInfo(
            docsStatus: docsReason == null ? _DocsStatus.verified : _DocsStatus.missing,
            missingReason: docsReason,
            isChildBike: false,
          ));
    } catch (e) {
      // Nezbylo nic — nezobrazíme docs sekci (raději nic, než matoucí stav)
      debugPrint('[Confirmation] docs status fetch error: $e');
      if (!mounted) return;
      setState(() => _info = const _ConfirmInfo(
            docsStatus: _DocsStatus.unknown,
            missingReason: null,
            isChildBike: false,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final moto = ref.watch(bookingMotoProvider);
    final dateFmt = DateFormat('d. M. yyyy');
    final tr = t(context);

    return PopScope(
      // Hardwarové „zpět" z děkovací stránky nesmí skončit na prázdném
      // zásobníku (sem se chodí přes `context.go` → není co popnout). Vždy
      // pošli zákazníka na přehled rezervací místo pádu na „Restartujte
      // aplikaci".
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.invalidate(reservationsProvider);
          context.go(Routes.reservations);
        }
      },
      child: Scaffold(
      backgroundColor: MotoGoColors.dark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mototematická oslava — motorka přeletí obrazovku,
                // jiskry + elastický check (viz moto_fx.dart)
                const MotoSuccessHero(),
                const SizedBox(height: 8),

                // Title
                StaggeredReveal(
                  index: 0,
                  child: Column(children: [
                    Text(
                      tr.tr('successTitle'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr.tr('successSubtitle'),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Booking details card
                if (draft.motoName != null || draft.startDate != null)
                  StaggeredReveal(
                    index: 1,
                    child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(MotoGoTheme.radiusSm),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (draft.motoName != null)
                          _detailRow(
                            '🏍️',
                            draft.motoName!,
                            bold: true,
                          ),
                        if (draft.startDate != null &&
                            draft.endDate != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '📅',
                            '${dateFmt.format(draft.startDate!)} – ${dateFmt.format(draft.endDate!)}',
                          ),
                        ],
                        if (moto?.branchName != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '📍',
                            moto!.branchName!,
                          ),
                        ],
                        if (draft.pickupTime != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '⏰',
                            '${tr.tr('pickupTimeLabel')}: ${draft.pickupTime}',
                          ),
                        ],
                        if (draft.returnTime != null) ...[
                          const SizedBox(height: 8),
                          _detailRow(
                            '⏰',
                            '${tr.tr('returnTimeLabel')}: ${draft.returnTime}',
                          ),
                        ],
                      ],
                    ),
                  ),
                  ),
                const SizedBox(height: 16),

                // Docs status — parita s webovou /potvrzeni
                // Skipujeme jen pro stav `unknown` (fallback bez bookingId)
                if (_info.docsStatus != _DocsStatus.unknown) ...[
                  StaggeredReveal(index: 2, child: _DocsStatusCard(info: _info)),
                  const SizedBox(height: 16),
                ],

                // Email confirmation info
                StaggeredReveal(
                  index: 3,
                  child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(MotoGoTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Text('📧',
                          style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr.tr('successEmailSent'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // Security tips
                StaggeredReveal(
                  index: 4,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MotoGoColors.amberBg,
                      borderRadius:
                          BorderRadius.circular(MotoGoTheme.radiusSm),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '⚠️ ${tr.tr('successSafetyTitle')}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr.tr('successSafetyTips'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF78350F),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sync badge
                StaggeredReveal(
                  index: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      '📡 ${tr.tr('successSynced')}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.g400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // CTA: pokud chybí doklady, primárka vede do Dokumentů (skenování)
                if (_info.docsStatus == _DocsStatus.missing)
                  StaggeredReveal(
                    index: 6,
                    child: PressableScale(
                      child: ElevatedButton(
                        onPressed: () {
                          ref.invalidate(reservationsProvider);
                          // `push` (ne `go`) — děkovací stránka zůstane v
                          // zásobníku, takže „zpět" z Dokladů se sem vrátí a
                          // nikdy nespadne na prázdný stack („Restartujte
                          // aplikaci"). Po nahrání dokladů se vrací sem.
                          context.push(Routes.docs);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          '${tr.tr('uploadDocumentsCta')} →',
                        ),
                      ),
                    ),
                  )
                else
                  StaggeredReveal(
                    index: 6,
                    child: PressableScale(
                      child: ElevatedButton(
                        onPressed: () {
                          ref.invalidate(reservationsProvider);
                          context.go(Routes.reservations);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(
                            '${tr.tr('successCta')} →'),
                      ),
                    ),
                  ),
                if (_info.docsStatus == _DocsStatus.missing) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      ref.invalidate(reservationsProvider);
                      context.go(Routes.reservations);
                    },
                    child: Text(
                      tr.tr('successCta'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _detailRow(String emoji, String text, {bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocsStatusCard extends StatelessWidget {
  final _ConfirmInfo info;
  const _DocsStatusCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final isOk = info.docsStatus == _DocsStatus.verified;
    final color = isOk ? const Color(0xFF166534) : const Color(0xFFB35900);
    final bg = isOk
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFFF1E6);
    final icon = isOk ? '✓' : '⚠';
    final title = isOk
        ? (info.isChildBike
            ? tr.tr('docsChildBikeTitle')
            : tr.tr('docsVerifiedTitle'))
        : tr.tr('docsMissingTitle');
    final body = isOk
        ? (info.isChildBike
            ? tr.tr('docsChildBikeBody')
            : tr.tr('docsVerifiedBody'))
        : (info.missingReason?.isNotEmpty == true
            ? '${info.missingReason}\n\n${tr.tr('docsMissingBody')}'
            : tr.tr('docsMissingBody'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon,
                  style: TextStyle(
                      fontSize: 18,
                      color: color,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }
}
