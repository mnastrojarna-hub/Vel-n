part of 'payment_screen.dart';

/// Zaplacená výměna motorky / úprava rezervace (D6) a doplatek do 1 Kč (D1).
///
/// Zápis změny po zaplacení dělá SERVER (webhook + `complete_extension`,
/// idempotentně); appka ho jen vyžádá přes trvalou frontu [PaidChangeQueue],
/// která přežije zabití appky i výpadek sítě. Zákazník po zaplacení nikdy
/// nevidí chybu: buď „hotovo", nebo „Výměna/Úprava se dokončuje".
extension _PaymentChanges on _PaymentScreenState {
  bool get _isSwap => _flow == PayFlow.swap;

  /// Položka fronty pro aktuální doplatek (null = nejde o doplatek změny
  /// nebo id PaymentIntentu neznáme).
  PaidChangeEntry? _paidChangeEntry({required bool paid}) {
    final key = _activePiId;
    final bid = _pendingBookingId;
    final ctx = _ctx;
    if (key == null || bid == null || ctx?.flowType != PaymentFlowType.extension) return null;
    final pending = ctx!.pendingEditChanges ?? const <String, dynamic>{};
    final swap = pending['_swap_commit'];
    final cc = cardCharge(_amount);
    Map<String, dynamic>? cols;
    if (swap is! Map) {
      cols = {for (final e in pending.entries) if (!e.key.startsWith('_')) e.key: e.value};
      // Cenu s dorovnáním drží server (card_rounding) — klient ji nepřepisuje.
      if (cc.rounding != 0) cols.remove('total_price');
    }
    return PaidChangeEntry(
      key: key,
      bookingId: bid,
      kind: swap is Map ? 'swap' : 'edit',
      charge: cc.charge.toDouble(),
      paid: paid,
      extras: pending['_extras_replace'] == true
          ? {
              'rows': pending['_extras_rows'] ?? const [],
              'del': pending['_extras_delete_ids'] ?? const [],
              'orig': pending['_extras_orig'] ?? const [],
            }
          : null,
      columns: cols,
      swap: swap is Map
          ? {
              'p_booking_id': swap['p_booking_id'],
              'p_new_moto_id': swap['p_new_moto_id'],
              'p_swap_date': swap['p_swap_date'],
              'p_swap_time': swap['p_swap_time'],
            }
          : null,
    );
  }

  /// Zapíše doplatek do trvalé fronty ([paid] = platba prokazatelně prošla).
  Future<void> _enqueuePaidChange({required bool paid, Duration delay = Duration.zero}) async {
    final e = _paidChangeEntry(paid: paid);
    if (e != null) await PaidChangeQueue.enqueue(e, delay: delay);
  }

  void _goResult(PaymentOutcome outcome) {
    if (!mounted) return;
    ref.read(paymentOutcomeProvider.notifier).state = outcome;
    context.go(Routes.paymentResult);
  }

  /// Doplatek zaplacen (nebo do 1 Kč odpuštěn a serverem zapsán) → dokončit.
  Future<void> _finishPaidChange() async {
    final tr = t(context);
    final bid = _pendingBookingId;
    final key = _activePiId;
    final cc = cardCharge(_amount);
    if (_waivedApplied) {
      // Server změnu zapsal bez platby — doplnit jen doplňky (nejsou v metadatech).
      final x = _waivedExtras();
      if (x != null && bid != null) {
        try {
          await applyExtrasOnce(bid, x);
        } catch (e) {
          debugPrint('[Payment] waived extras: $e');
        }
      }
      if (!mounted) return;
      await _showChangeDone(tr, bid, newMotoId: _swapMotoId);
      return;
    }
    if (key == null || bid == null) {
      // Id platby neznáme (ztracená odpověď) → dokončí server (webhook);
      // výsledek ověří obrazovka „Platba se ověřuje".
      _goResult(pendingEditOutcome(tr,
          bookingId: bid ?? '',
          expectedTotal: _expectedEditTotal,
          intentOnly: _isSwap,
          verified: _editSuccessOutcome(tr)));
      return;
    }
    final r = await PaidChangeQueue.completeNow(key);
    if (!mounted) return;
    ref.invalidate(reservationsProvider);
    ref.invalidate(reservationByIdProvider(bid));
    switch (r.status) {
      case PaidChangeStatus.done:
        await _showChangeDone(tr, bid, newMotoId: _swapMotoId);
      case PaidChangeStatus.completing:
        _goResult(completingOutcome(tr,
            swap: _isSwap,
            key: key,
            bookingId: bid,
            amount: cc.charge.toDouble(),
            verified: _editSuccessOutcome(tr),
            offline: r.offline));
      case PaidChangeStatus.failed:
        await PaidChangeQueue.acknowledge(key);
        _goResult(changeFailedOutcome(tr,
            swap: _isSwap, bookingId: bid, r: r, charge: cc.charge.toDouble()));
      case PaidChangeStatus.notPaid:
        _goResult(PaymentOutcome(
          kind: PaymentOutcomeKind.failed,
          title: tr.tr('psNotPaidTitle'),
          subtitle: tr.tr('psNotPaidEdit'),
          ctaLabel: tr.tr('psOpenReservation'),
          ctaRoute: '/reservations/$bid',
        ));
    }
  }

  String? get _swapMotoId {
    final s = _ctx?.pendingEditChanges?['_swap_commit'];
    return s is Map ? s['p_new_moto_id']?.toString() : null;
  }

  Map<String, dynamic>? _waivedExtras() {
    final p = _ctx?.pendingEditChanges;
    if (p == null || p['_extras_replace'] != true) return null;
    return {
      'rows': p['_extras_rows'] ?? const [],
      'del': p['_extras_delete_ids'] ?? const [],
      'orig': p['_extras_orig'] ?? const [],
    };
  }

  /// Změna je zapsaná → výsledek „hotovo" (+ „K vyzvednutí").
  Future<void> _showChangeDone(AppTranslations tr, String? bid, {String? newMotoId}) async {
    if (bid != null && !_isSwap && !_waivedApplied) {
      // Úprava (ne výměna — tu rozesílá RPC sama): e-mail + doklady.
      EmailService.sendBookingModified(bid);
      InvoiceService.generateAdvanceInvoice(bid, cardCharge(_amount).charge.toDouble());
      InvoiceService.generateBookingDocs(bid);
    }
    final pickup = _isSwap
        ? await loadMotoPickupInfo(newMotoId)
        : await loadBookingPickupInfo(bid);
    if (!mounted) return;
    if (bid != null) {
      ref.invalidate(reservationsProvider);
      ref.invalidate(reservationByIdProvider(bid));
    }
    _goResult(_editSuccessOutcome(tr, pickup: pickup));
  }

  /// Doplatek do 1 Kč (D1): server změnu zapíše hned a nic neúčtuje.
  Future<void> _applyWaivedChange() async {
    _setProcessing(true);
    _markSubmitted();
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: 0,
      type: _stripeType,
      change: _extensionChangePayload,
      attemptId: newAttemptId(),
    );
    if (!mounted) return;
    if (result.type == PaymentResultType.free && result.applied) {
      _waivedApplied = true;
      _onPaymentSuccess();
      return;
    }
    // Okno nasazení (server ještě bez dorovnání u výměny): drobný rozdíl do
    // 0,50 Kč zapíše výměna jako dřív přímo (bez platby i bez záznamu).
    if (_isSwap &&
        PaymentRefusals.codeOf(result) == 'rounding_unavailable' &&
        _amount <= 0.5 &&
        await _commitSwapDirect()) {
      if (!mounted) return;
      _waivedApplied = true;
      _onPaymentSuccess();
      return;
    }
    if (!mounted) return;
    _setProcessing(false);
    _handleIntentError(result);
  }

  /// Přímý zápis výměny bez platby (jen okno nasazení, viz výše).
  Future<bool> _commitSwapDirect() async {
    final s = _ctx?.pendingEditChanges?['_swap_commit'];
    if (s is! Map) return false;
    try {
      final res = await MotoGoSupabase.client.rpc('split_booking_moto_swap', params: {
        'p_booking_id': s['p_booking_id'],
        'p_new_moto_id': s['p_new_moto_id'],
        'p_swap_date': s['p_swap_date'],
        'p_swap_time': s['p_swap_time'],
        'p_dry_run': false,
      }).timeout(const Duration(seconds: 20));
      final code = res is Map ? res['error']?.toString() : null;
      return (res is Map && res['success'] == true) ||
          code == 'already_split' ||
          code == 'invalid_new_moto';
    } catch (e) {
      debugPrint('[Payment] swap direct commit: $e');
      return false;
    }
  }

  /// Odpověď „bez platby" (100% sleva / odpuštěno do 1 Kč) z jakékoli cesty.
  void _handleFreeResult(PaymentResult r) {
    if (_ctx?.flowType == PaymentFlowType.extension) _waivedApplied = true;
    _onPaymentSuccess();
  }
}
