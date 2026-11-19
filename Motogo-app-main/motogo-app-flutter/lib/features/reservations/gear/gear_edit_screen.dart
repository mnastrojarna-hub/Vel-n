import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/flag/v2_scope.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../booking/self_service_gear.dart';
import '../../gear_rental/gear_contract.dart';
import '../reservation_models.dart';
import '../v2/res_gear_edit_v2.dart';
import '../widgets/res_cancel_dialog.dart';
import 'gear_booking_api.dart';
import 'gear_edit_api.dart';
import 'gear_edit_view.dart';
import 'gear_links.dart';
import 'gear_models.dart';

/// Úprava výpůjčky JEN výbavy (oba vzhledy): velikosti zdarma, odebrání
/// kusu (náhled vratky ze serveru), změna termínu na webu, storno. Žádný
/// přímý update řádku — jen RPC (gear_edit_api.dart). Termín: appka zatím
/// neumí zaplatit doplatek gear změny (GEAR_RENTAL_APP_EDIT.md §6) → web.
class GearEditScreen extends ConsumerStatefulWidget {
  final Reservation res;
  final VoidCallback onBack;
  final Future<void> Function() onReload;
  const GearEditScreen({super.key, required this.res, required this.onBack, required this.onReload});

  @override
  ConsumerState<GearEditScreen> createState() => _GearEditState();
}

class _GearEditState extends ConsumerState<GearEditScreen> {
  Map<String, String> _orig = {};
  Map<String, String> _sel = {};
  Map<String, Map<String, int>>? _avail;
  bool _busy = false;
  String? _done;
  String? _err;
  String? _pick;
  final Map<String, Object?> _prev = {};

  Reservation get res => widget.res;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant GearEditScreen old) {
    super.didUpdateWidget(old);
    if (old.res != widget.res) _init();
  }

  void _init() {
    _orig = {for (final e in gearItemSizes(res).entries) if (e.value.isNotEmpty) e.key: e.value};
    _sel = Map.of(_orig);
    _pick = null;
    _prev.clear();
    if (gearSizesEditable(res)) {
      fetchGearAvailability(res).then((a) {
        if (mounted) setState(() => _avail = a);
      });
    }
  }

  Map<String, String> get _changed => {
        for (final e in _sel.entries)
          if (_orig[e.key] != e.value) e.key: e.value,
      };

  List<GearSizeRowData> _sizeRows(AppTranslations tr, List<GearPrice>? prices) => [
        for (final k in _orig.keys)
          () {
            final row = prices?.where((p) => p.key == k && !p.isSet).firstOrNull;
            var list = (row != null && row.sizes.isNotEmpty) ? row.sizes : [_orig[k]!];
            if (res.isSelfService) list = selfServiceGearSizes(k, list);
            if (!list.contains(_orig[k])) list = [_orig[k]!, ...list];
            return GearSizeRowData(
              key: k,
              label: row?.label ?? tr.tr(k),
              sizes: list,
              soldOut: {for (final s in list) if (_avail?[k]?[s] == 0 && s != _orig[k]) s},
              selected: _sel[k] ?? _orig[k]!,
              orig: _orig[k]!,
            );
          }(),
      ];

  void _pickSize(String key, String size) => setState(() {
        _sel[key] = size;
        _done = null;
        _err = null;
      });

  Future<void> _saveSizes() async {
    final ch = _changed;
    if (ch.isEmpty || _busy) return;
    final tr = t(context);
    setState(() => _busy = true);
    final r = await gearRpc('customer_update_gear_sizes', {'p_booking_id': res.id, 'p_sizes': ch});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = r.ok ? tr.tr('gearSizesSaved') : null;
      _err = r.ok ? null : gearEditErrorText(tr, r.error);
    });
    if (r.ok) _afterChange();
  }

  void _choose(String key) {
    setState(() {
      _pick = _pick == key ? null : key;
      _done = null;
      _err = null;
    });
    final k = _pick;
    if (k == null || _prev.containsKey(k)) return;
    _prev[k] = 'loading';
    gearRpc('customer_remove_gear_item', {'p_booking_id': res.id, 'p_key': k, 'p_dry_run': true}).then((r) {
      if (!mounted) return;
      setState(() {
        if (r.ok) {
          _prev[k] = GearRemovePreview.fromJson(r.data!, res);
        } else if (r.error == 'network' || r.error == 'failed') {
          _prev.remove(k); // výpadek: další výběr zkusí znovu
        } else {
          _prev[k] = r.error;
        }
      });
    });
  }

  Future<void> _remove(String label) async {
    final k = _pick;
    if (k == null || _busy) return;
    final tr = t(context);
    final yes = await showMgConfirm(
      context,
      title: tr.trArgs('gearRemoveConfirm', {'item': label}),
      safeLabel: tr.tr('cancel'),
      actionLabel: tr.tr('gearRemoveYes'),
      destructive: true,
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    final r = await gearRpc('customer_remove_gear_item', {'p_booking_id': res.id, 'p_key': k, 'p_dry_run': false});
    if (!mounted) return;
    final amt = (r.data?['refund_amount'] as num?)?.toDouble() ?? 0;
    final pct = (r.data?['refund_percent'] as num?)?.toInt() ?? 0;
    setState(() {
      _busy = false;
      _err = r.ok ? null : gearEditErrorText(tr, r.error);
      _done = !r.ok
          ? null
          : amt > 0
              ? tr.trArgs('gearRemoveSuccess', {'item': label, 'amount': Money.czk(amt), 'percent': pct})
              : tr.trArgs('gearRemoveSuccessNoRefund', {'item': label});
    });
    if (r.ok) _afterChange();
  }

  void _afterChange() {
    refreshGearBookings(ref, res.id);
    widget.onReload();
  }

  Future<void> _cancel() async {
    await showDialog<void>(context: context, builder: (_) => ResCancelDialog(reservation: res));
    if (!mounted) return;
    _afterChange();
  }

  Future<void> _openWebDates() =>
      openGearWeb(gearWebEditUri(res.id, ref.read(localeProvider).languageCode));

  /// Text náhledu odebrání (null = vyber kus / načítá se).
  (String?, bool) _removeSummary(AppTranslations tr) {
    final p = _pick == null ? null : _prev[_pick];
    if (_pick == null) return (tr.tr('gearRemovePick'), false);
    if (p == 'loading') return (null, false);
    if (p is String) return (gearEditErrorText(tr, p), false);
    if (p is GearRemovePreview) {
      final head = '${tr.tr('gearNewPerDay')}: ${Money.czk(p.perDay)}';
      if (p.noSaving) return ('$head\n${tr.tr('gearRemoveNoSaving')}', true);
      if (p.percent == 0 || p.refund <= 0) return ('$head\n${tr.tr('gearRemoveNoRefund')}', true);
      return ('$head\n${tr.trArgs('gearRemoveRefund', {'amount': Money.czk(p.refund), 'percent': p.percent})}', true);
    }
    return (tr.tr('gearRemoveServerCalc'), true);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final prices = ref.watch(gearPricesProvider).valueOrNull;
    final labels = prices == null ? null : {for (final p in prices) p.key: p.label};
    final items = gearItemSizes(res);
    final (removeText, removeOk) = _removeSummary(tr);
    final data = GearEditData(
      title: tr.tr('gearEditTitle'),
      subtitle: '${res.shortId} · ${res.dateRange}',
      summary: gearSummary(res, tr, labels),
      done: _done,
      error: _err,
      busy: _busy,
      closedNote: gearDatesEditable(res) ? null : (gearCanPay(res) ? tr.tr('gearPendingText') : tr.tr('gearEditClosed')),
      sizes: gearSizesEditable(res) ? _sizeRows(tr, prices) : null,
      selfService: res.isSelfService,
      sizesChanged: _changed.isNotEmpty,
      removeItems: gearRemoveAllowed(res)
          ? [for (final e in items.entries) GearRemoveItemData(key: e.key, label: labels?[e.key] ?? tr.tr(e.key), size: e.value)]
          : null,
      removePick: _pick,
      removeText: removeText,
      removeOk: removeOk,
      datesWeb: gearDatesEditable(res),
      canCancel: gearCancelAllowed(res),
    );
    final actions = GearEditActions(
      onBack: widget.onBack,
      onPickSize: _pickSize,
      onSaveSizes: _saveSizes,
      onChooseRemove: _choose,
      onRemove: () => _remove(labels?[_pick] ?? tr.tr(_pick ?? '')),
      onDatesWeb: _openWebDates,
      onCancel: _cancel,
    );
    if (MgV2.on(context)) return ResGearEditV2(data: data, actions: actions);
    return GearEditOldView(data: data, actions: actions);
  }
}
