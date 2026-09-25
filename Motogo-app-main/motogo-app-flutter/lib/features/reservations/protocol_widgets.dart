import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';

/// Bílá karta sekce protokolu (stav km, kontroly, výbava, podpis…).
Widget protocolCard({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
      child: child,
    );

/// Nadpis sekce uvnitř karty.
Widget protocolTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
    );

/// Zaškrtávací řádek (celý řádek je klikací).
Widget protocolToggleRow(String label, bool checked, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: checked ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: checked ? MotoGoColors.green : MotoGoColors.g200, width: 2),
            ),
            child: checked ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MotoGoColors.black))),
        ]),
      ),
    );

/// Informační střed obrazovky (obslužná pobočka, zatím nelze vyplnit, chyba).
Widget protocolInfoCenter(String emoji, String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: MotoGoColors.black, fontWeight: FontWeight.w600)),
        ]),
      ),
    );

/// Zamčený pohled po podpisu — protokol je v Dokumentech, měnit už nejde.
class ProtocolLockedView extends StatelessWidget {
  final bool autofilled;
  const ProtocolLockedView({super.key, required this.autofilled});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        protocolCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('✅', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(tr.tr(autofilled ? 'hpSignedAutoTitle' : 'hpSignedTitle'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker))),
            ]),
            const SizedBox(height: 8),
            Text(tr.tr(autofilled ? 'hpSignedAutoText' : 'hpSignedText'),
                style: const TextStyle(fontSize: 13, color: MotoGoColors.black, height: 1.4)),
          ]),
        ),
        ElevatedButton.icon(
          onPressed: () => context.push(Routes.contracts),
          icon: const Icon(Icons.description, size: 18),
          label: Text(tr.tr('hpShowDocs')),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.messages),
          icon: const Icon(Icons.report_problem_outlined, size: 18),
          label: Text(tr.tr('hpReport')),
        ),
        const SizedBox(height: 8),
        Text(tr.tr('hpReportHint'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
        const SizedBox(height: 40),
      ]),
    );
  }
}

/// Podpis prstem — kresba do plátna, export PNG (data-URL) přes RepaintBoundary.
class ProtocolSignaturePad extends StatefulWidget {
  const ProtocolSignaturePad({super.key});

  @override
  State<ProtocolSignaturePad> createState() => ProtocolSignaturePadState();
}

class ProtocolSignaturePadState extends State<ProtocolSignaturePad> {
  final _key = GlobalKey();
  final List<Offset?> _strokes = [];
  bool _has = false;

  bool get hasSignature => _has;

  void clear() => setState(() { _strokes.clear(); _has = false; });

  /// PNG jako data-URL (pixelRatio 2), null při chybě renderu.
  Future<String?> capture() async {
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      return 'data:image/png;base64,${base64Encode(bd.buffer.asUint8List())}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(tr.tr('hpSignature'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
        TextButton(onPressed: clear, child: Text(tr.tr('hpClear'))),
      ]),
      Text(tr.tr('hpSignHint'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
      const SizedBox(height: 8),
      RepaintBoundary(
        key: _key,
        child: Container(
          height: 160,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: MotoGoColors.g200, width: 1.5), borderRadius: BorderRadius.circular(10)),
          child: GestureDetector(
            onPanStart: (d) => setState(() { _strokes.add(d.localPosition); _has = true; }),
            onPanUpdate: (d) => setState(() => _strokes.add(d.localPosition)),
            onPanEnd: (_) => _strokes.add(null),
            child: CustomPaint(painter: _SignaturePainter(_strokes), size: Size.infinite),
          ),
        ),
      ),
    ]);
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true; // tahy mutují in-place
}
