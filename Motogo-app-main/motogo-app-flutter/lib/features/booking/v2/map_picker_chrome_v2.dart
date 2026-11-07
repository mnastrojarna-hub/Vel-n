import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// v2 chrome of the full-screen address map picker (CB-05, V22 §6.4
/// "Výběr adresy"): back 44 (photo style) + title over a night fade, the
/// pin, a white r16 result card ("Hledám adresu…" with a 16 px spinner,
/// then street 15/800 + city 12.5/600) and ONE ink primary "Potvrdit
/// adresu". The map, geocoding and the result are the picker's own; this
/// only draws on top (the map keeps every drag outside the controls).
class MapPickerChromeV2 extends StatelessWidget {
  final bool loading;
  final String street;
  final String cityLine;
  final String fullAddress;
  final VoidCallback onBack;
  final VoidCallback? onConfirm;

  const MapPickerChromeV2({
    super.key,
    required this.loading,
    required this.street,
    required this.cityLine,
    required this.fullAddress,
    required this.onBack,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final mq = MediaQuery.of(context);
    final title = street.isNotEmpty ? street : fullAddress;
    return Stack(children: [
      // Pin: its tip marks the map centre.
      const IgnorePointer(
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: _Pin(),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: MgStatusBar(
          dark: true,
          child: Container(
            padding: EdgeInsets.fromLTRB(MgSpace.gutter, mq.padding.top + 8, MgSpace.gutter, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MgColors.nightA(0.85), MgColors.nightA(0)],
              ),
            ),
            child: Row(children: [
              MgV2Back(onTap: onBack, style: MgBackStyle.photo),
              const SizedBox(width: MgSpace.s12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: MgWordFit(
                    minScale: 0.8,
                    child: Text(tr.tr('v2UxCbMapTitle'), style: MgType.title.copyWith(fontSize: 17, color: MgColors.onDark)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      Positioned(
        left: MgSpace.gutter,
        right: MgSpace.gutter,
        bottom: mq.padding.bottom + MgSpace.s16,
        child: Container(
          padding: const EdgeInsets.all(MgSpace.card),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.card),
            boxShadow: MgShadows.sheet,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              liveRegion: true,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: MgIcon(MgIcons.pin, size: 22, color: MgColors.link),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: loading
                      ? Row(children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(tr.tr('searchingAddress'),
                                style: MgType.body.copyWith(color: MgColors.lead)),
                          ),
                        ])
                      : title.isEmpty
                          ? Text(tr.tr('v2UxCbMapMove'), style: MgType.body.copyWith(color: MgColors.lead))
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: MgType.title.copyWith(color: MgColors.ink)),
                              if (street.isNotEmpty && cityLine.isNotEmpty)
                                Text(cityLine, style: MgType.small.copyWith(color: MgColors.lead)),
                            ]),
                ),
              ]),
            ),
            const SizedBox(height: MgSpace.s12),
            MgBtnInk(label: tr.tr('confirmAddressAction'), onTap: onConfirm),
          ]),
        ),
      ),
    ]);
  }
}

/// Map pin: ink disc with a neon dot on a short stem (no emoji, v1 §2.9).
class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: MgColors.ink,
            shape: BoxShape.circle,
            border: Border.all(color: MgColors.surface, width: 2.5),
            boxShadow: MgShadows.photoControl,
          ),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
            ),
          ),
        ),
        Container(width: 3, height: 8, color: MgColors.ink),
      ]);
}
