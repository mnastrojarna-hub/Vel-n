import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/moto_fx.dart';
import '../../auth/widgets/toast_helper.dart';
import '../reservation_models.dart';
import '../ride_feedback.dart';
import 'res_rating_widgets.dart' show RatingMiniStars;
import '../../../core/friendly_error.dart';
import '../../../core/widgets/mg_nav_controls.dart';

/// Otevře sheet „Napiš nám přímo, co máme zlepšit“. Vrací id konverzace,
/// do které zpráva odešla (null = zavřeno bez odeslání).
Future<String?> showRideFeedbackSheet(BuildContext context, {required Reservation res, required int rating}) async {
  Future<RideFeedbackResult>? sending;
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RideFeedbackSheet(res: res, rating: rating, onSending: (f) => sending = f),
  );
  final pending = sending;
  if (id != null || pending == null) return id;
  // Sheet zavřený (stažení / klepnutí mimo / zpět) BĚHEM odesílání: zpráva
  // dál odchází → počkej na výsledek, ať karta potvrdí odeslání (jinak by
  // zákazník psal znovu) nebo aspoň oznámí chybu.
  final result = await pending;
  if (!result.ok && context.mounted) {
    final tr = t(context);
    showMotoGoToast(context, icon: '⚠️', title: tr.error, message: tr.tr('rfSendFailed'));
  }
  return result.threadId;
}

class _RideFeedbackSheet extends StatefulWidget {
  final Reservation res;
  final int rating;
  /// Probíhající odeslání (null = nic neodchází) — pro [showRideFeedbackSheet].
  final ValueChanged<Future<RideFeedbackResult>?> onSending;
  const _RideFeedbackSheet({required this.res, required this.rating, required this.onSending});

  @override
  State<_RideFeedbackSheet> createState() => _RideFeedbackSheetState();
}

class _RideFeedbackSheetState extends State<_RideFeedbackSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  /// Klepnuto na Odeslat s prázdným textem → hláška přímo pod polem
  /// (toast by zůstal schovaný pod klávesnicí — AppShell nemění výšku).
  bool _emptyTried = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final tr = t(context);
    if (_ctrl.text.trim().isEmpty) {
      HapticFeedback.lightImpact();
      setState(() => _emptyTried = true);
      return;
    }
    final route = ModalRoute.of(context);
    setState(() => _sending = true);
    final pending = sendRideFeedback(
      shortId: widget.res.shortId,
      subjectPrefix: tr.tr('rfThreadSubject'),
      rating: widget.rating,
      text: _ctrl.text,
    );
    widget.onSending(pending);
    final result = await pending;
    // Sheet mezitím zavřený → výsledek převzal showRideFeedbackSheet (a pop
    // by teď zavřel obrazovku POD sheetem).
    if (!mounted || !(route?.isActive ?? false)) return;
    widget.onSending(null);
    if (result.ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(result.threadId);
    } else {
      setState(() => _sending = false);
      // Důvod + rada; text zůstává v políčku.
      showMotoGoToast(context,
          icon: '⚠️',
          title: tr.tr('eoMessageSendWhat'),
          message: '${FriendlyError.of(result.cause).compose(tr, tr.tr('eoMessageSendWhat'))} ${tr.tr('eoTextKept')}',
          duration: const Duration(seconds: 7));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final canSend = _ctrl.text.trim().isNotEmpty && !_sending;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(MotoGoRadius.hdr)),
        ),
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.of(context).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MgSheetHandle(),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text('✍️', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.tr('rfImproveBtn'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black, height: 1.2)),
                    const SizedBox(height: 2),
                    Text('${widget.res.motoName} · ${widget.res.shortId}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
                  ]),
                ),
                if (widget.rating > 0) RatingMiniStars(rating: widget.rating, size: 13),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🔒', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr.tr('rfSheetInfo'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g600, height: 1.4)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                maxLength: kRideFeedbackMaxLen,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: MotoGoColors.black, height: 1.4),
                decoration: InputDecoration(
                  hintText: tr.tr('rfSheetHint'),
                  hintMaxLines: 3,
                  hintStyle: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                  filled: true,
                  fillColor: MotoGoColors.g100,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.xl), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                      borderSide: const BorderSide(color: MotoGoColors.greenDark, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14),
                  errorText: _emptyTried && _ctrl.text.trim().isEmpty ? tr.tr('rfEmpty') : null,
                  errorMaxLines: 2,
                  errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.red),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                      borderSide: const BorderSide(color: MotoGoColors.red)),
                  focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                      borderSide: const BorderSide(color: MotoGoColors.red, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              // Prázdný text → tlačítko šedé, klepnutí vysvětlí proč (hláška pod polem).
              PressableScale(
                enabled: !_sending,
                onTap: _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: canSend || _sending ? MotoGoColors.green : MotoGoColors.g200,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    boxShadow: canSend
                        ? [BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _sending
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: MotoGoColors.black))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(tr.tr('send'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                          const SizedBox(width: 8),
                          const Icon(Icons.send_rounded, size: 18, color: MotoGoColors.black),
                        ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
