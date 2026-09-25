import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../documents/booking_doc_viewer.dart' show bookingDocsProvider;
import 'protocol_gear.dart';
import 'protocol_widgets.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';

/// Předávací protokol pro SAMOOBSLUŽNOU pobočku — zákazník vyplní a podepíše
/// prstem v appce (nebo na displeji pobočky). Bez podepsaného protokolu kiosk
/// kóji motorky neotevře; automatické vyplnění po hodině bylo 2026-09-25 zrušeno.
/// Otevírá se bannerem/tlačítkem v detailu rezervace a VYNUCENĚ (přes celou
/// obrazovku) po výzvě z kiosku — `handover_protocol_prompted_at`
/// (HandoverPromptWatcher). Po podpisu kdekoli (appka, kiosk, Velín) zmizí
/// real-time: sleduje stream rezervací. Podepsané PDF zůstává v Dokumentech.
class ProtocolScreen extends ConsumerStatefulWidget {
  final Reservation? reservation;
  const ProtocolScreen({super.key, this.reservation});

  /// Rezervace, pro které je obrazovka protokolu právě otevřená —
  /// HandoverPromptWatcher pak výzvu z kiosku nevnucuje podruhé nad ni.
  static final Set<String> openFor = <String>{};

  @override
  ConsumerState<ProtocolScreen> createState() => _ProtocolState();
}

class _Check {
  final String key;
  final String i18n;
  bool checked;
  _Check(this.key, this.i18n, {this.checked = false});
}

/// Chyba edge funkce v těle 200 (`{success:false, error:'…'}`).
class _EdgeError implements Exception {
  final String code;
  const _EdgeError(this.code);
  @override
  String toString() => code;
}

/// Kódy chyb `submit-handover-protocol` → i18n klíč (jinak obecné „Uložení selhalo“).
const _edgeErrorKeys = {
  'too_early': 'hpNotYet',
  'wrong_status': 'hpErrWrongStatus',
  'not_self_service': 'hpStaffed',
  'invalid_signature': 'hpSignFailed',
  'missing_signature': 'hpSignMissing',
  'signature_too_large': 'hpErrSigTooLarge',
  'not_found': 'hpNotFound',
  'forbidden': 'hpNotFound',
};

class _ProtocolState extends ConsumerState<ProtocolScreen> {
  bool _loading = true;
  bool _submitting = false;
  bool _closing = false; // obrazovka se zavírá (podpis náš/odjinud) → stream ani další submit neřešit
  String? _error;
  Map<String, dynamic>? _state; // get_handover_protocol_state
  Map<String, List<String>> _sizes = const {};

  final _mileageCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _damageCtrl = TextEditingController();
  bool _damage = false;
  final _sig = GlobalKey<ProtocolSignaturePadState>();

  late final List<ProtocolGearItem> _gear =
      widget.reservation == null ? <ProtocolGearItem>[] : buildProtocolGear(widget.reservation!);

  late final List<_Check> _checks = [
    _Check('clean', 'hpCheckClean', checked: true),
    _Check('docs', 'hpCheckDocs', checked: true),
    _Check('keys', 'hpCheckKeys', checked: true),
    _Check('instructed', 'hpCheckInstructed', checked: true),
    // Výbava „předána“ jen když si zákazník něco půjčuje (parita s kioskem).
    _Check('gear', 'hpCheckGear', checked: _gear.isNotEmpty),
  ];

  late final List<_Check> _extraGear = [
    _Check('phone_holder', 'hpXPhoneHolder'),
    _Check('usb_adapter', 'hpXUsb'),
    _Check('disc_lock', 'hpXDiscLock'),
    _Check('rain_suit', 'hpXRainSuit'),
    _Check('rain_boots', 'hpXRainBoots'),
    _Check('rain_gloves', 'hpXRainGloves'),
    _Check('tie_net', 'hpXTieNet'),
    _Check('tankbag_small', 'hpXTankbagS'),
    _Check('tankbag_large', 'hpXTankbagL'),
    _Check('reflective', 'hpXReflective'),
    _Check('back_protector', 'hpXBackProtector'),
    _Check('chain_spray', 'hpXChainSpray'),
  ];

  @override
  void initState() {
    super.initState();
    final id = widget.reservation?.id;
    if (id != null) ProtocolScreen.openFor.add(id);
    _init();
  }

  Future<void> _init() async {
    final r = widget.reservation;
    if (r == null) {
      // Text až v build (v initState nejde číst Localizations) — viz _buildBody.
      setState(() { _loading = false; _error = ''; });
      return;
    }
    // Jen ČTENÍ stavu — okno protokolu spouští výhradně kiosk (zavření šatny /
    // kód motorky), ne otevření obrazovky (start_handover_protocol_window
    // se už nevolá).
    try {
      final st = await MotoGoSupabase.client.rpc('get_handover_protocol_state', params: {'p_booking_id': r.id});
      final sizes = await loadProtocolGearSizes(kids: r.motoLicenseRequired == 'N');
      if (!mounted) return;
      setState(() { _state = (st as Map?)?.cast<String, dynamic>(); _sizes = sizes; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  void dispose() {
    final id = widget.reservation?.id;
    if (id != null) ProtocolScreen.openFor.remove(id);
    _mileageCtrl.dispose();
    _notesCtrl.dispose();
    _damageCtrl.dispose();
    super.dispose();
  }

  void _invalidate(String id) {
    ref.invalidate(bookingDocsProvider(id));
    ref.invalidate(handoverProtocolStateProvider(id));
    ref.invalidate(reservationByIdProvider(id));
    ref.invalidate(reservationsProvider);
  }

  /// Zavře TUTO obrazovku. Je top-level route: dropdown velikosti nebo dialog
  /// otevřený nad ní by `context.pop()` sundal místo ní (formulář by zůstal
  /// „zavřený“ napořád) — proto nejdřív popUntil na vlastní route.
  void _popSelf() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
    context.backOr(Routes.reservations);
  }

  /// Podepsáno jinde (displej pobočky / jiné zařízení / Velín) → zavřít.
  void _closeSignedElsewhere() {
    if (_closing || !mounted) return;
    _closing = true;
    final id = widget.reservation?.id;
    if (id != null) _invalidate(id);
    showMotoGoToast(context, icon: '✅', title: t(context).tr('handoverProtocol'), message: t(context).tr('protocolSignedElsewhere'));
    _popSelf();
  }

  /// Text chyby odeslání: kód edge funkce (4xx → FunctionException.details,
  /// 200 → `_EdgeError`) přeložený zákazníkovi; neznámé → „Uložení selhalo: …“.
  String _submitErrorText(Object e) {
    String? code;
    if (e is _EdgeError) {
      code = e.code;
    } else if (e is FunctionException) {
      final d = e.details;
      code = d is Map ? d['error']?.toString() : null;
    }
    final key = _edgeErrorKeys[code];
    return key != null ? t(context).tr(key) : '${t(context).tr('hpSubmitFailed')}: ${code ?? e}';
  }

  Future<void> _submit() async {
    final r = widget.reservation;
    if (r == null || _submitting || _closing) return;
    final sig = _sig.currentState;
    if (sig == null || !sig.hasSignature) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('hpSignature'), message: t(context).tr('hpSignMissing'));
      return;
    }
    setState(() => _submitting = true);
    final signature = await sig.capture();
    if (signature == null) {
      if (mounted) {
        setState(() => _submitting = false);
        showMotoGoToast(context, icon: '⚠️', title: t(context).tr('hpSignature'), message: t(context).tr('hpSignFailed'));
      }
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
      // {key, who, field, label, size, checked} — edge propíše upravené
      // velikosti do bookings.<field> před claimem podpisu.
      'accessories': _gear.map((g) => g.toJson()).toList(),
    };
    try {
      final res = await MotoGoSupabase.client.functions.invoke(
        'submit-handover-protocol',
        body: {'booking_id': r.id, 'mode': 'customer', 'form': form, 'signature': signature},
      );
      final data = res.data;
      final ok = data is Map && data['success'] == true;
      if (!ok) throw _EdgeError((data is Map ? data['error']?.toString() : null) ?? 'submit_failed');
      if (!mounted) return;
      if (data['already_filled'] == true) {
        // Podepsáno souběžně jinde (kiosk/Velín) — zavřít stejně jako ze streamu.
        _closeSignedElsewhere();
        return;
      }
      _closing = true;
      _invalidate(r.id);
      showMotoGoToast(context, icon: '✅', title: t(context).tr('handoverProtocol'), message: t(context).tr('protocolSignedToast'));
      _popSelf();
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: _submitErrorText(e));
    } finally {
      // Vždy odemknout tlačítko — i po already_filled / podpisu odjinud, kdyby
      // obrazovka z jakéhokoli důvodu zůstala na displeji.
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Real-time: podpis odjinud (kiosk/Velín) → obrazovka se sama zavře.
    ref.listen(reservationsProvider, (prev, next) {
      final id = widget.reservation?.id;
      if (id == null || _closing || _submitting) return;
      final list = next.valueOrNull;
      if (list == null) return;
      final fresh = list.where((x) => x.id == id).firstOrNull;
      if (fresh != null && fresh.protocolSigned && _state?['locked'] != true) {
        // Navigace až po frame — listener může přijít uprostřed vykreslování.
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeSignedElsewhere());
      }
    });
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
        title: Text('📝 ${t(context).tr('handoverProtocol')}'),
        backgroundColor: MotoGoColors.dark,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MotoGoColors.green))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text(_error!.isEmpty ? t(context).tr('hpNotFound') : _error!, style: const TextStyle(color: MotoGoColors.g400))))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _state ?? {};
    if (s['is_self_service'] != true) return protocolInfoCenter('🏢', t(context).tr('hpStaffed'));
    if (s['locked'] == true) return ProtocolLockedView(autofilled: s['autofilled'] == true);
    if (s['can_fill'] == true) return _buildForm();
    return protocolInfoCenter('⏳', t(context).tr('hpNotYet'));
  }

  Widget _buildForm() {
    final tr = t(context);
    final r = widget.reservation!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Hlavička — motorka a termín (stejné jako na displeji pobočky)
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.motoName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
          const SizedBox(height: 2),
          Text('${r.dateRange} · ${r.shortId}', style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
        ])),
        // Stav km
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpMileage')),
          TextField(controller: _mileageCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'km')),
        ])),
        // Kontrola převzetí
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpChecks')),
          ..._checks.map(_checkRow),
        ])),
        // Zapůjčená výbava — velikosti upravitelné dle toho, co si vzal v šatně
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpGear')),
          if (_gear.isEmpty)
            Text(tr.tr('hpNoGear'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400))
          else ...[
            Text(tr.tr('hpGearHint'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
            const SizedBox(height: 8),
            ..._gear.map(_gearRow),
          ],
        ])),
        // Doplňkové vybavení
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpExtraGear')),
          ..._extraGear.map(_checkRow),
        ])),
        // Poškození
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpDamage')),
          protocolToggleRow(tr.tr('hpDamageAtPickup'), _damage, () => setState(() => _damage = !_damage)),
          if (_damage) ...[
            const SizedBox(height: 8),
            TextField(controller: _damageCtrl, maxLines: 2, decoration: InputDecoration(hintText: tr.tr('hpDamageDesc'))),
          ],
        ])),
        // Poznámky
        protocolCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          protocolTitle(tr.tr('hpNotes')),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: InputDecoration(hintText: tr.tr('hpOptional'))),
        ])),
        // Podpis
        protocolCard(child: ProtocolSignaturePad(key: _sig)),
        const SizedBox(height: 4),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text(tr.tr('hpSubmit'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _checkRow(_Check c) =>
      protocolToggleRow(t(context).tr(c.i18n), c.checked, () => setState(() => c.checked = !c.checked));

  /// Řádek výbavy: zaškrtnutí (předáno) + popisek + dropdown velikosti z číselníku.
  Widget _gearRow(ProtocolGearItem g) {
    // Uložená velikost mimo číselník (starý ceník) musí být v nabídce — jinak
    // DropdownButton spadne na chybějící hodnotě.
    final opts = List<String>.from(_sizes[g.key] ?? const <String>[]);
    if (g.size != null && !opts.contains(g.size)) opts.insert(0, g.size!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => g.checked = !g.checked),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: g.checked ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: g.checked ? MotoGoColors.green : MotoGoColors.g200, width: 2),
            ),
            child: g.checked ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(g.label(t(context)), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MotoGoColors.black))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: DropdownButton<String>(
            value: g.size,
            hint: Text(t(context).tr('hpSize'), style: const TextStyle(fontSize: 12)),
            underline: const SizedBox(),
            isDense: true,
            dropdownColor: Colors.white,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black),
            items: opts.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (s) => setState(() => g.size = s),
          ),
        ),
      ]),
    );
  }
}
