import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../catalog/catalog_provider.dart';
import 'branches_info_provider.dart';
import 'branches_widgets.dart';

/// Detail pobočky (`/pobocky/<index>`) — obdoba webu /pobocky/<slug>: texty
/// z Velína (`web.pobocky.branches.<i>.*`), video (nahrané ve Velínu nebo
/// odkaz na YouTube; prázdné = bez videa), navigace a rezervace.
class BranchDetailScreen extends ConsumerWidget {
  final int index;
  const BranchDetailScreen({super.key, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider).languageCode;
    final tx = ref.watch(branchesInfoProvider(lang)).valueOrNull ?? branchesInfoDefaults;
    final i = index.clamp(0, branchesInfoMapQueries.length - 1);
    String? v(String k) => tx['branches.$i.$k'];
    final video = (v('video') ?? '').trim();

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: branchesAppBar(context, plainText(v('title') ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: branchesCardDecoration(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              branchBadge(v('badge')),
              const SizedBox(height: 10),
              richText(v('title'), const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              const SizedBox(height: 8),
              branchLine('📍', v('address'), branchesBodyStyle),
              branchLine('🕑', v('hours'), branchesBodyStyle),
              const SizedBox(height: 6),
              richText(v('text'), branchesBodyStyle),
              const SizedBox(height: 8),
              branchLine('🧥', v('gear'), branchesBodyStyle),
              const SizedBox(height: 6),
              richText(v('steps_title'), const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.dark)),
              const SizedBox(height: 4),
              richText(v('steps'), branchesBodyStyle),
              if (video.startsWith('https://')) ...[
                const SizedBox(height: 16),
                richText(v('video_title'), const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.dark)),
                const SizedBox(height: 8),
                BranchVideo(key: ValueKey(video), url: video),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(branchesInfoMapQueries[i])}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: Text(t(context).tr('branchesNavigate')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MotoGoColors.greenDarker,
                    side: const BorderSide(color: MotoGoColors.green),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          branchesCtaBox(context, tx, onBook: () => _bookHere(context, ref, i)),
          const SizedBox(height: 90),
        ],
      ),
    );
  }

  /// „Rezervovat" z detailu pobočky → výpis motorek JEN této pobočky.
  /// Čerstvý filtr (pobočka + případně už zvolený termín) — staré filtry
  /// (kategorie, výkon…) by s pobočkou mohly dát prázdný výpis. Pobočku,
  /// kterou katalog nenabízí (trvale zavřená), nepředvybírá — výpis by byl
  /// prázdný; dokud se motorky ještě načítají, předvybere ji rovnou.
  void _bookHere(BuildContext context, WidgetRef ref, int i) {
    final id = i < branchesInfoBranchIds.length ? branchesInfoBranchIds[i] : null;
    final loaded = ref.read(motorcyclesProvider).hasValue;
    if (id != null && (!loaded || ref.read(branchesProvider).any((b) => b['id'] == id))) {
      final f = ref.read(catalogFilterProvider);
      ref.read(catalogFilterProvider.notifier).state =
          CatalogFilter(branch: id, startDate: f.startDate, endDate: f.endDate);
    }
    context.go(Routes.search);
  }
}
