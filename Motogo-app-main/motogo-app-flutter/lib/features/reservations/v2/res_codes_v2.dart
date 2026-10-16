import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_toast.dart';

/// One door code as `ResAccessCodesCard` computed it (label, value or the
/// withheld reason, protocol-first note).
class ResCodeV2Item {
  final String label;
  final String value;
  final bool sent;
  final bool protocolNote;
  const ResCodeV2Item({required this.label, required this.value, required this.sent, this.protocolNote = false});
}

/// Dark look of `ResAccessCodesCard` inside CO TEĎ (V22 `.cd` tiles 1 → 2
/// → 3). DUMB: the card keeps the codes stream, the order (gate → locker →
/// moto), the withheld logic and the release action; this only draws them.
class ResCodesV2 extends StatelessWidget {
  final String? gateCode;
  final List<ResCodeV2Item> codes;
  final bool ownGearNoLocker;
  final VoidCallback? onRelease;
  final bool loading;
  final String? errorText;
  final VoidCallback? onRetry;
  final VoidCallback? onMessages;
  final VoidCallback? onCall;

  const ResCodesV2({
    super.key,
    required this.gateCode,
    required this.codes,
    required this.ownGearNoLocker,
    required this.onRelease,
  })  : loading = false,
        errorText = null,
        onRetry = null,
        onMessages = null,
        onCall = null;

  const ResCodesV2.loading({super.key})
      : gateCode = null,
        codes = const [],
        ownGearNoLocker = false,
        onRelease = null,
        loading = true,
        errorText = null,
        onRetry = null,
        onMessages = null,
        onCall = null;

  const ResCodesV2.error({
    super.key,
    required String this.errorText,
    required this.onRetry,
    required this.onMessages,
    required this.onCall,
  })  : gateCode = null,
        codes = const [],
        ownGearNoLocker = false,
        onRelease = null,
        loading = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final head = Row(children: [
      const MgIcon(MgIcons.key, size: 18, color: MgColors.neon),
      const SizedBox(width: 8),
      Expanded(child: Text(tr.tr('accessCodes'), style: MgType.title.copyWith(color: MgColors.onDark))),
      if (loading)
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.neon)),
    ]);
    if (loading) return Padding(padding: const EdgeInsets.only(top: 16), child: head);
    if (errorText != null) {
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MgColors.errDarkBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.errDark.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          head,
          const SizedBox(height: 6),
          Text(errorText!, style: MgType.small.copyWith(color: MgColors.onDarkBody)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 0, children: [
            MgBtnText(label: tr.tr('eoRetry'), onTap: onRetry, dark: true, icon: MgIcons.refresh),
            MgBtnText(label: tr.tr('messagesFromMotoGo'), onTap: onMessages, dark: true, icon: MgIcons.chat),
            MgBtnText(label: tr.tr('eoCall'), onTap: onCall, dark: true, icon: MgIcons.phone),
          ]),
        ]),
      );
    }
    var n = 0;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (gateCode != null) ...[
          _tile(context, ++n, tr.tr('gateCodeLabel'), gateCode!, true, sub: tr.tr('gateCodeHint')),
        ],
        for (final c in codes) ...[
          _tile(context, ++n, c.label, c.value, c.sent,
              sub: c.protocolNote ? tr.tr('protocolFirst') : null, subWarn: c.protocolNote),
        ],
        if (ownGearNoLocker)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.neonA(0.35)),
            ),
            child: Row(children: [
              const MgIcon(MgIcons.info, size: 18, color: MgColors.neon),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${tr.tr('lockerCode')} · ${tr.tr('ownGearNoLocker')}',
                    style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              ),
            ]),
          ),
        if (onRelease != null) ...[
          const SizedBox(height: 12),
          MgCta(label: tr.tr('uploadDocsForCodes'), onTap: onRelease, size: MgCtaSize.sm48, showMarks: false),
        ],
      ]),
    );
  }

  Widget _tile(BuildContext context, int n, String label, String value, bool sent, {String? sub, bool subWarn = false}) {
    final tr = t(context);
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text('$n', style: MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
            if (!sent)
              Text(value, style: MgType.meta.copyWith(color: MgColors.warnDark))
            else if (sub != null)
              Text(sub, style: MgType.meta.copyWith(color: subWarn ? MgColors.warnDark : MgColors.onDarkSecondary)),
          ]),
        ),
      ),
      if (!sent)
        const SizedBox(
          width: 44,
          height: 44,
          child: Center(child: MgIcon(MgIcons.lock, size: 20, color: MgColors.warnDark)),
        ),
    ]);
    return MgEnter(
      delay: Duration(milliseconds: 80 * n),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
        decoration: BoxDecoration(
          color: MgColors.white(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sent ? MgColors.neonA(0.25) : MgColors.warnDark.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          if (sent)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Row(children: [
                Expanded(
                  child: Text(value, style: MgType.tab(MgType.code.copyWith(fontSize: 30, color: MgColors.neon))),
                ),
                Semantics(
                  button: true,
                  label: '${tr.tr('v2ResCopyCode')} · $label',
                  excludeSemantics: true,
                  child: MgPress(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (!context.mounted) return;
                      showMgToast(context, tr.tr('copiedToClipboard'), icon: MgIcons.copy);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: MgColors.neonA(0.14), borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: MgIcon(MgIcons.copy, size: 20, color: MgColors.neonText)),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
