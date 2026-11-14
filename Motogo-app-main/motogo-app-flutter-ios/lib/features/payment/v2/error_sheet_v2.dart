import 'package:flutter/material.dart';

import '../../../core/v2/states/mg_state_sheet.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 body of `PaymentErrorSheet` (Stavy T2; serves payment, e-shop
/// checkout, booking restore and reservation edit): light sheet with the
/// grabber, ✕ 44 ALWAYS visible (terminal state: ✕ = the main action, as
/// the old sheet did), error disc (one shake), left title, the message as
/// the "why", pinned ink primary + ghost secondary. Every button first
/// closes the sheet, then calls the caller's callback — the old order.
/// No support row (owner D5). Drag / dismiss flags stay the caller's.
class PaymentErrorSheetV2 extends StatelessWidget {
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback? onButton;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool dismissible;

  const PaymentErrorSheetV2({
    super.key,
    required this.title,
    required this.message,
    required this.buttonLabel,
    this.onButton,
    this.secondaryLabel,
    this.onSecondary,
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    void main() {
      Navigator.of(context).pop();
      onButton?.call();
    }

    return MgSheetFrame(
      onClose: dismissible ? null : main,
      footer: MgSheetButtons(
        primary: MgBtnInk(label: mgStripEmoji(buttonLabel), onTap: main),
        secondary: secondaryLabel == null
            ? null
            : MgBtnGhostLight(
                label: mgStripEmoji(secondaryLabel!),
                onTap: () {
                  Navigator.of(context).pop();
                  onSecondary?.call();
                },
              ),
      ),
      child: MgStateSheetBody(
        tone: MgTone.err,
        title: mgStripEmoji(title),
        why: message,
        support: false,
      ),
    );
  }
}
