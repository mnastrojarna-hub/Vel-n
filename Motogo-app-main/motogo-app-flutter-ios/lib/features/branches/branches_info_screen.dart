import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../profile/widgets/branches_sheet.dart';
import 'branches_info_provider.dart';

/// Pobočky (Profil → Pobočky, na místě dočasně skrytého e-shopu, 2026-10-01).
/// Obsah = texty z Velína (`web.pobocky.*`) shodné s webem `/pobocky`.
class BranchesInfoScreen extends ConsumerWidget {
  const BranchesInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider).languageCode;
    final async = ref.watch(branchesInfoProvider(lang));
    final tx = async.valueOrNull ?? branchesInfoDefaults;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.canPop() ? context.pop() : context.go(Routes.profile),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Text(t(context).tr('branchesLabel')),
        backgroundColor: MotoGoColors.dark,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(branchesInfoProvider(lang).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _rich(tx['h1'], const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            _rich(tx['intro'], const TextStyle(fontSize: 14, height: 1.45, color: MotoGoColors.g600)),
            const SizedBox(height: 16),
            for (var i = 0; i < branchesInfoMapQueries.length; i++) _BranchCard(tx: tx, i: i),
            _ctaBox(context, tx),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showBranchesSheet(context),
              icon: const Text('🏍️'),
              label: Text(t(context).tr('branchesMotos')),
              style: OutlinedButton.styleFrom(
                foregroundColor: MotoGoColors.dark,
                side: const BorderSide(color: MotoGoColors.g200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
              ),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _ctaBox(BuildContext context, Map<String, String> tx) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _rich(tx['cta.title'], const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 6),
          _rich(tx['cta.text'], const TextStyle(fontSize: 13, height: 1.4, color: MotoGoColors.dark)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.go(Routes.search),
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.dark, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
            ),
            child: Text(_plain(tx['cta.button'] ?? ''), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _BranchCard extends StatelessWidget {
  final Map<String, String> tx;
  final int i;
  const _BranchCard({required this.tx, required this.i});

  @override
  Widget build(BuildContext context) {
    String? v(String k) => tx['branches.$i.$k'];
    const body = TextStyle(fontSize: 13.5, height: 1.45, color: MotoGoColors.g600);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
          child: Text(_plain(v('badge') ?? '').toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.dark)),
        ),
        const SizedBox(height: 10),
        _rich(v('title'), const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
        const SizedBox(height: 8),
        _line('📍', v('address'), body),
        _line('🕑', v('hours'), body),
        const SizedBox(height: 6),
        _rich(v('text'), body),
        const SizedBox(height: 8),
        _line('🧥', v('gear'), body),
        const SizedBox(height: 6),
        _rich(v('steps_title'), const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.dark)),
        const SizedBox(height: 4),
        _rich(v('steps'), body),
        const SizedBox(height: 12),
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
    );
  }

  Widget _line(String icon, String? html, TextStyle style) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$icon ', style: style),
          Expanded(child: _rich(html, style)),
        ]),
      );
}

/// CMS texty jsou HTML z editoru Velína — tučné (<strong>/<b>) zachováme,
/// zalomení (<br>, odstavce, div) převedeme na nové řádky, ostatní tagy zahodíme.
Widget _rich(String? html, TextStyle style) {
  final src = (html ?? '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>\s*<(p|div|li)[^>]*>', caseSensitive: false), '\n');
  final spans = <TextSpan>[];
  var bold = false;
  for (final part in src.split(RegExp(r'(?=<)|(?<=>)'))) {
    final tag = RegExp(r'^<\s*(/?)\s*(strong|b)\b', caseSensitive: false).firstMatch(part);
    if (tag != null) {
      bold = tag.group(1) != '/';
    } else if (!part.startsWith('<')) {
      final s = _decode(part);
      if (s.isNotEmpty) spans.add(TextSpan(text: s, style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null));
    }
  }
  return Text.rich(TextSpan(style: style, children: spans));
}

String _plain(String html) => _decode(html.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

String _decode(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
