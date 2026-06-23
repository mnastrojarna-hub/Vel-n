import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import 'reservation_models.dart';

/// Předávací protokol pro SAMOOBSLUŽNOU pobočku — zákazník vyplní a podepíše
/// sám na tabletu v appce. Po zadání kódu ke dveřím běží 1h okno; pokud do hodiny
/// nevyplní, systém protokol vyplní automaticky („vše dle rezervace, vše OK").
/// Po vyplnění je protokol zamčený (needituje se) a viditelný v Dokumentech;
/// nesrovnalosti zákazník hlásí jen zprávou v appce nebo e-mailem.
class ProtocolScreen extends StatefulWidget {
  final Reservation? reservation;
  const ProtocolScreen({super.key, this.reservation});

  @override
  State<ProtocolScreen> createState() => _ProtocolState();
}

class _HandoverCheck {
  final String key;
  final String label;
  bool checked;
  _HandoverCheck(this.key, this.label, {this.checked = false});
}

class _AccessoryItem {
  final String label;
  final String size;
  bool checked;
  _AccessoryItem(this.label, this.size, {this.checked = true});
}

class _ProtocolState extends State<ProtocolScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _state; // get_handover_protocol_state

  final _mileageCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  bool _damage = false;

  final _sigKey = GlobalKey();
  final List<Offset?> _strokes = [];
  bool _hasSignature = false;

  late final List<_HandoverCheck> _checks = [
    _HandoverCheck('clean', 'Motocykl předán čistý a v provozuschopném stavu', checked: true),
    _HandoverCheck('docs', 'Doklady k vozidlu (OTP, zelená karta) předány', checked: true),
    _HandoverCheck('keys', 'Klíče a zabezpečení předány', checked: true),
    _HandoverCheck('instructed', 'Nájemce poučen o obsluze a provozu', checked: true),
    _HandoverCheck('gear', 'Ochranná výbava předána a vyzkoušena', checked: true),
  ];

  late final List<_HandoverCheck> _extraGear = [
    _HandoverCheck('phone_holder', 'Držák na telefon'),
    _HandoverCheck('disc_lock', 'Kotoučový zámek'),
    _HandoverCheck('rain_suit', 'Set nepromokavé bundy a kalhot'),
    _HandoverCheck('rain_boots', 'Nepromoky na nohy'),
    _HandoverCheck('rain_gloves', 'Nepromoky na ruce'),
    _HandoverCheck('tie_net', 'Upínací síťka'),
    _HandoverCheck('tankbag_small', 'Tankvak malý'),
    _HandoverCheck('tankbag_large', 'Tankvak velký'),
    _HandoverCheck('reflective', 'Reflexní prvky'),
    _HandoverCheck('back_protector', 'Páteřák'),
    _HandoverCheck('chain_spray', 'Sprej na řetěz'),
  ];

  late final List<_AccessoryItem> _accessories = _buildAccessories();

  List<_AccessoryItem> _buildAccessories() {
    final r = widget.reservation;
    final out = <_AccessoryItem>[];
    if (r == null) return out;
    void add(String label, String? size) {
      if (size != null && size.isNotEmpty) out.add(_AccessoryItem(label, size));
    }
    add('Helma (řidič)', r.helmetSize);
    add('Bunda (řidič)', r.jacketSize);
    add('Kalhoty (řidič)', r.pantsSize);
    add('Boty (řidič)', r.bootsSize);
    add('Rukavice (řidič)', r.glovesSize);
    add('Helma (spolujezdec)', r.passengerHelmetSize);
    add('Bunda (spolujezdec)', r.passengerJacketSize);
    add('Kalhoty (spolujezdec)', r.passengerPantsSize);
    add('Boty (spolujezdec)', r.passengerBootsSize);
    return out;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final r = widget.reservation;
    if (r == null) {
      setState(() { _loading = false; _error = 'Rezervace nenalezena.'; });
      return;
    }
    try {
      // Spustí 1h okno (idempotentní — jen poprvé). Zákazník zadal kód na tabletu.
      await MotoGoSupabase.client.rpc('start_handover_protocol_window', params: {'p_booking_id': r.id});
    } catch (_) { /* okno není kritické pro zobrazení */ }
    try {
      final st = await MotoGoSupabase.client.rpc('get_handover_protocol_state', params: {'p_booking_id': r.id});
      setState(() { _state = (st as Map?)?.cast<String, dynamic>(); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  void dispose() {
    _mileageCtrl.dispose();
    _notesCtrl.dispose();
    _damageCtrl.dispose();
    super.dispose();
  }

  Future<String?> _captureSignature() async {
    try {
      final boundary = _sigKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      final bytes = bd.buffer.asUint8List();
      return 'data:image/png;base64,${base64Encode(bytes)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final r = widget.reservation;
    if (r == null) return;
    if (!_hasSignature) {
      showMotoGoToast(context, icon: '⚠️', title: 'Podpis', message: 'Podepište se prosím prstem.');
      return;
    }
    setState(() => _submitting = true);
    final signature = await _captureSignature();
    if (signature == null) {
      setState(() => _submitting = false);
      showMotoGoToast(context, icon: '⚠️', title: 'Podpis', message: 'Podpis se nepodařilo uložit, zkuste znovu.');
      return;
    }
    final checks = <String, bool>{};
    for (final c in _checks) checks[c.key] = c.checked;
    for (final c in _extraGear) checks[c.key] = c.checked;
    final form = {
      'mileage': _mileageCtrl.text.trim(),
      'checks': checks,
      'damage': {'checked': _damage, 'desc': _damageCtrl.text.trim()},
      'notes': _notesCtrl.text.trim(),
      'accessories': _accessories.map((a) => {'label': a.label, 'size': a.size, 'checked': a.checked}).toList(),
    };
    try {
      final res = await MotoGoSupabase.client.functions.invoke(
        'submit-handover-protocol',
        body: {'booking_id': r.id, 'mode': 'customer', 'form': form, 'signature': signature},
      );
      final data = res.data;
      final ok = data is Map && data['success'] == true;
      if (!ok) throw Exception((data is Map ? data['error'] : null) ?? 'Odeslání selhalo');
      if (!mounted) return;
      showMotoGoToast(context, icon: '✅', title: 'Hotovo', message: 'Předávací protokol byl uložen.');
      await _init(); // reload → locked stav
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '⚠️', title: 'Chyba', message: 'Uložení selhalo: $e');
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.backOr(Routes.reservations),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: const Text('📝 Předávací protokol'),
        backgroundColor: MotoGoColors.dark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MotoGoColors.green))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: MotoGoColors.g400))))
              : _buildBody(),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
        child: child,
      );

  Widget _buildBody() {
    final s = _state ?? {};
    if (s['is_self_service'] != true) {
      return _infoCenter('🏢', 'Tuto rezervaci předává obsluha pobočky. Předávací protokol vyplní personál.');
    }
    if (s['locked'] == true) {
      return _buildLocked(s['autofilled'] == true);
    }
    if (s['can_fill'] == true) {
      return _buildForm(s);
    }
    return _infoCenter('⏳', 'Protokol zatím nelze vyplnit. Nejdřív zadejte na tabletu kód ke dveřím u motorky.');
  }

  Widget _infoCenter(String emoji, String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: MotoGoColors.black, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _buildLocked(bool autofilled) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('✅', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(autofilled ? 'Protokol vyplněn automaticky' : 'Protokol vyplněn a podepsán',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker))),
            ]),
            const SizedBox(height: 8),
            Text(autofilled
                ? 'Nestihli jste protokol vyplnit do hodiny, proto jsme jej vyplnili automaticky — motocykl byl převzat dle rezervace a vše je v pořádku. Protokol najdete v Dokumentech.'
                : 'Děkujeme. Podepsaný protokol najdete v Dokumentech u této rezervace. Protokol už nelze měnit.',
                style: const TextStyle(fontSize: 13, color: MotoGoColors.black, height: 1.4)),
          ]),
        ),
        ElevatedButton.icon(
          onPressed: () => context.push(Routes.contracts),
          icon: const Icon(Icons.description, size: 18),
          label: const Text('Zobrazit v Dokumentech'),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.messages),
          icon: const Icon(Icons.report_problem_outlined, size: 18),
          label: const Text('Nahlásit nesrovnalost'),
        ),
        const SizedBox(height: 8),
        const Text('Případné nesrovnalosti nahlaste zprávou v appce nebo e-mailem na info@motogo24.cz.',
            style: TextStyle(fontSize: 11, color: MotoGoColors.g400)),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildForm(Map<String, dynamic> s) {
    final deadline = DateTime.tryParse('${s['deadline'] ?? ''}')?.toLocal();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (deadline != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
            child: Text('Protokol vyplňte do ${_fmtTime(deadline)}. Pokud nestihnete, vyplníme jej automaticky (vše dle rezervace).',
                style: const TextStyle(fontSize: 12, color: MotoGoColors.greenDarker, fontWeight: FontWeight.w600)),
          ),
        // Stav km
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stav km při převzetí', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          TextField(controller: _mileageCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'km')),
        ])),
        // Kontrola předání
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kontrola převzetí', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          ..._checks.map((c) => _checkRow(c)),
        ])),
        // Příslušenství
        if (_accessories.isNotEmpty)
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Zapůjčené příslušenství', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 8),
            ..._accessories.map((a) => _accessoryRow(a)),
          ])),
        // Doplňkové vybavení
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Doplňkové vybavení', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          ..._extraGear.map((c) => _checkRow(c)),
        ])),
        // Poškození
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Poškození', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          _toggleRow('Poškození při převzetí', _damage, () => setState(() => _damage = !_damage)),
          if (_damage) ...[
            const SizedBox(height: 8),
            TextField(controller: _damageCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Popis poškození')),
          ],
        ])),
        // Poznámky
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Poznámky', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 8),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Volitelné')),
        ])),
        // Podpis
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Podpis nájemce', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            TextButton(onPressed: () => setState(() { _strokes.clear(); _hasSignature = false; }), child: const Text('Vymazat')),
          ]),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _sigKey,
            child: Container(
              height: 160,
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: MotoGoColors.g200, width: 1.5), borderRadius: BorderRadius.circular(10)),
              child: GestureDetector(
                onPanStart: (d) => setState(() { _strokes.add(d.localPosition); _hasSignature = true; }),
                onPanUpdate: (d) => setState(() => _strokes.add(d.localPosition)),
                onPanEnd: (_) => _strokes.add(null),
                child: CustomPaint(painter: _SignaturePainter(_strokes), size: Size.infinite),
              ),
            ),
          ),
        ])),
        const SizedBox(height: 4),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Uložit a podepsat protokol', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  String _fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _checkRow(_HandoverCheck c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _toggleRow(c.label, c.checked, () => setState(() => c.checked = !c.checked)),
      );

  Widget _accessoryRow(_AccessoryItem a) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _toggleRow('${a.label} — ${a.size}', a.checked, () => setState(() => a.checked = !a.checked)),
      );

  Widget _toggleRow(String label, bool checked, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
      );
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
