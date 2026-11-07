import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// "Odesláno" after a community submit (board TrasaDetail "Odesláno
/// (dialog)", V21 T19): ✓ tone disc (dark, check draws + pop + one ripple;
/// static under reduced motion), "Díky! Návrh odeslán", the moderation
/// sentence and ONE ink "Hotovo". Same texts and the same close as the old
/// sheet — the caller awaits it, then pops its screen.
Future<void> showSubmitSuccessV2(BuildContext context) => showMgDialog<void>(
      context,
      builder: (c) {
        final tr = t(c);
        return MgDialogFrame(
          content: Column(children: [
            const MgToneDisc(tone: MgTone.ok, size: 64, dark: true),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              liveRegion: true,
              child: MgWordFit(
                minScale: 0.75,
                alignment: Alignment.center,
                child: Text(tr.tr('submitSuccessTitle'),
                    textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
              ),
            ),
            const SizedBox(height: 8),
            Text(tr.tr('submitSuccessBody'), textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
          ]),
          action: MgBtnInk(label: tr.tr('submitSuccessOk'), onTap: () => Navigator.of(c).pop()),
        );
      },
    );
