import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import 'ai_chat_parts_v2.dart';

/// AI servisní agent in the v2 look (PLAN §2.5.2, seam view of
/// `AiAgentScreen`): dark chat (V22 R5.10) — header with the logo tile,
/// glass / neon bubbles, error bubbles with "Zkusit znovu", the red SOS
/// card, typing dots, photo attach (≤ 3, existing picker) and a dark input
/// bar. Nav + AI FAB are hidden on this route. All logic stays in the State.
class AiChatViewV2 extends ConsumerWidget {
  final List<AiChatItemV2> items;
  final bool sending;
  final bool slow;
  final List<Uint8List> pendingImages;
  final ValueChanged<int> onRemoveImage;
  final TextEditingController inputCtrl;
  final ScrollController scrollCtrl;
  final VoidCallback onBack;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onSos;

  const AiChatViewV2({
    super.key,
    required this.items,
    required this.sending,
    required this.slow,
    required this.pendingImages,
    required this.onRemoveImage,
    required this.inputCtrl,
    required this.scrollCtrl,
    required this.onBack,
    required this.onSend,
    required this.onAttach,
    required this.onSos,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: MgColors.night,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: MgGradients.hero(rank.aura)),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: MgColors.onDarkBody),
          child: Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(12, mq.padding.top + 8, 16, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.white(0.08)))),
              child: Row(children: [
                MgV2Back(onTap: onBack, style: MgBackStyle.dark),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/logo.webp',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: 36,
                            height: 36,
                            color: MgColors.neon,
                            child: const Center(child: MgIcon(MgIcons.ai, size: 20, color: MgColors.onNeon)),
                          )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(
                      header: true,
                      child: Text(tr.tr('aiServiceAgent'), style: MgType.title.copyWith(color: MgColors.onDark)),
                    ),
                    Text(tr.tr('v2PfAiSub'), style: MgType.meta.copyWith(fontWeight: FontWeight.w600, color: MgColors.neonText)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: items.length + (sending ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (i == items.length) {
                    return AiTypingV2(label: tr.tr(slow ? 'eoAiStillThinking' : 'aiThinking'));
                  }
                  final m = items[i];
                  if (m.isSosHint) return MgEnter(child: AiSosCardV2(onTap: onSos));
                  return AiBubbleV2(item: m, sending: sending);
                },
              ),
            ),
            if (pendingImages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  for (var i = 0; i < pendingImages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: MgPop(
                        playOnMount: true,
                        child: Stack(clipBehavior: Clip.none, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(pendingImages[i],
                                width: 56, height: 56, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: 56, height: 56, color: MgColors.panel)),
                          ),
                          Positioned(
                            top: -10,
                            right: -10,
                            child: Semantics(
                              button: true,
                              label: tr.tr('close'),
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onRemoveImage(i),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: MgColors.ink,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: MgColors.panel, width: 2),
                                    ),
                                    child: const Center(child: MgIcon(MgIcons.close, size: 14, color: MgColors.onDark)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            Container(
              padding: EdgeInsets.fromLTRB(12, 12, 12, mq.padding.bottom + 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: MgColors.white(0.08)))),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: tr.tr('aiTakePhoto'),
                  excludeSemantics: true,
                  child: MgPress(
                    onTap: onAttach,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: MgColors.white(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: pendingImages.isEmpty ? MgColors.neonA(0.3) : MgColors.neon, width: 1.5),
                      ),
                      child: Center(
                        child: MgIcon(MgIcons.camera,
                            size: 22, color: pendingImages.isEmpty ? MgColors.onDarkMeta : MgColors.neon),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: inputCtrl,
                    maxLines: null,
                    cursorColor: MgColors.neon,
                    style: MgType.body.copyWith(color: MgColors.onDark),
                    decoration: InputDecoration(
                      hintText: tr.tr('aiDescribeProblemHint'),
                      hintStyle: MgType.body.copyWith(color: MgColors.onDarkMeta),
                      filled: true,
                      fillColor: MgColors.white(0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: MgColors.neonA(0.3), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: MgColors.neon, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: tr.tr('send'),
                  excludeSemantics: true,
                  child: MgPress(
                    scale: 0.92,
                    onTap: onSend,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(gradient: MgGradients.neon, shape: BoxShape.circle, boxShadow: MgShadows.icon),
                      child: const Center(child: MgIcon(MgIcons.send, size: 20, color: MgColors.onNeon, stroke: 2.2)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
