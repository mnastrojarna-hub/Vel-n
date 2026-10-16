part of 'payment_screen.dart';

/// Chybové a nejisté stavy platby (2026-10-16, požadavek majitele): každá
/// chyba říká CO se stalo, PROČ a JAK dál — a tlačítko vždy něco udělá.
/// Nikdy syrový text výjimky / Stripe / serveru, nikdy „nic nestrženo",
/// když to nevíme, nikdy nabídka další platby, dokud se ta první ověřuje.
extension _PaymentProblems on _PaymentScreenState {
  String get _counter {
    final tr = t(context);
    return '\n\n(${tr.tr('attempt')} $_attempts ${tr.tr('of')} $maxPaymentAttempts)';
  }

  void _showError({
    required String title,
    required String message,
    required String buttonLabel,
    VoidCallback? onButton,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool dismissible = true,
  }) {
    if (!mounted) return;
    PaymentErrorSheet.show(
      context,
      title: title,
      message: message,
      buttonLabel: buttonLabel,
      onButton: onButton,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      dismissible: dismissible,
    );
  }

  /// Odmítnutí / chyba z `createPaymentIntent` (server, síť, přihlášení).
  void _handleIntentError(PaymentResult result) {
    _showProblem(PaymentRefusals.resolve(t(context).lang, result, _flow,
        amount: _amount));
  }

  /// Zobrazí [p] s akcí, která opravdu něco dělá (žádné „Zkusit znovu",
  /// které jen zavře sheet).
  void _showProblem(PayProblem p) {
    if (!mounted) return;
    final tr = t(context);
    switch (p.action) {
      case PayAction.success:
        showMotoGoToast(context, icon: '✓', title: tr.tr('paid'), message: p.message);
        _onPaymentSuccess();
        return;
      case PayAction.pending:
        _goPending();
        return;
      case PayAction.verify:
        _verifyUncertain();
        return;
      default:
        break;
    }
    if (p.countsAsAttempt) {
      _attempts++;
      if (_attempts >= maxPaymentAttempts) {
        _handleMaxAttempts();
        return;
      }
    }
    final edit = _flow == PayFlow.edit || _flow == PayFlow.swap;
    String label;
    VoidCallback? onTap;
    String? second;
    VoidCallback? onSecond;
    switch (p.action) {
      case PayAction.priceChanged:
        final total = p.serverTotal ?? 0;
        label = tr.tr('psPayAmount').replaceAll('{amount}', Money.czk(total));
        onTap = () {
          // K nové rezervaci se platí i upsell z e-shopu (server ho povoluje navíc).
          final upsell = _isNewBooking ? ref.read(bookingUpsellProvider.notifier).total : 0.0;
          _set(() => _serverAmount = total + upsell);
          _doPayment();
        };
        second = tr.back;
      case PayAction.belowMinimum:
        if (_flow == PayFlow.resume) {
          // Dokončovaná / obnovená rezervace: nezaplacenou rezervaci v
          // Rezervacích upravit nejde (D1) → hlavní krok je „Napsat nám".
          label = tr.tr('psWriteUs');
          onTap = () => openContactUs(context);
          second = tr.tr('psMyReservations');
          onSecond = () => context.go(Routes.reservations);
        } else {
          label = tr.tr(edit ? 'psEditChange' : 'psEditBooking');
          onTap = () => context.backOr(_backFallback);
        }
      case PayAction.reloadEdit:
        label = tr.tr('psReload');
        onTap = () => context.go(_editRoute);
      case PayAction.editAddress:
        label = tr.tr('psEditAddress');
        onTap = () => context.backOr(_editRoute);
      case PayAction.editBooking:
        label = tr.tr('psEditBooking');
        onTap = () => context.backOr(Routes.booking);
      case PayAction.toCart:
        label = tr.tr('psToCart');
        onTap = () => context.go(Routes.cart);
      case PayAction.signIn:
        label = tr.tr('login');
        // Přihlášení ještě běží (jiný účet / odmítnutý token) → bez odhlášení
        // by router z /login hned vrátil Domů a nic by se nestalo.
        onTap = () => signInAgain(context);
      case PayAction.reservations:
        label = tr.tr('psMyReservations');
        onTap = () => context.go(Routes.reservations);
      default:
        label = tr.tr('retry');
        onTap = _doPayment;
    }
    if (p.contact && second == null) {
      second = tr.tr('psWriteUs');
      onSecond = () => openContactUs(context);
    }
    _showError(
      title: p.title,
      message: p.countsAsAttempt ? p.message + _counter : p.message,
      buttonLabel: label,
      onButton: onTap,
      secondaryLabel: second,
      onSecondary: onSecond,
    );
  }

  /// Selhání stržení uložené karty (zamítnutí / 3DS nedokončeno). Tlačítko
  /// „Zkusit znovu" znovu strhne ULOŽENOU kartu — nikdy samo neotevře
  /// zadávání karty; „Zaplatit jinou kartou" je výslovná volba zákazníka.
  /// [notCharged] = server kartu prokazatelně nestrhával (nepotvrzený intent).
  void _handleSavedCardFailure(PaymentResult result,
      {bool authNotDone = false, bool authFailed = false, bool notCharged = false}) {
    final lang = t(context).lang;
    final tr = t(context);
    PaymentErrorInfo info;
    if (authNotDone) {
      info = PaymentErrorInfo(
          title: PaymentErrorMapper.text(lang, 'authTitle'),
          message: tr.tr('psAuthNotDone'));
    } else if (authFailed) {
      info = PaymentErrorInfo(
          title: PaymentErrorMapper.text(lang, 'authTitle'),
          message: PaymentErrorMapper.text(lang, 'authBody'));
    } else if (notCharged) {
      info = PaymentErrorMapper.generic(lang);
      _attempts++;
    } else {
      info = PaymentErrorMapper.fromEdge(
          errorCode: result.stripeCode,
          declineCode: result.declineCode,
          intentStatus: result.intentStatus,
          lang: lang);
      if (info.needsVerification) {
        _verifyUncertain();
        return;
      }
      if (info.cause == 'amount_too_small') {
        _showProblem(PaymentRefusals.belowMinimum(lang, _flow, _amount));
        return;
      }
      _attempts++;
    }
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    // Uložená karta už neexistuje / nejde použít → jediná smysluplná akce
    // je jiná karta (opakování by selhalo stejně).
    if (info.cause == 'card_gone') {
      _showError(
        title: info.title,
        message: info.message,
        buttonLabel: tr.tr('payWithAnotherCard'),
        onButton: () => _runPaymentSheetFlow(_amount),
      );
      return;
    }
    _showError(
      title: info.title,
      message: info.message + _counter,
      buttonLabel: tr.tr('retry'),
      onButton: () {
        // Znovu strhni ULOŽENOU kartu (žádný Payment Sheet).
        final card = ref.read(defaultCardProvider);
        if (!mounted) return;
        if (card != null && card.stripeId.isNotEmpty) {
          _setProcessing(true);
          _chargeSavedCard(_amount, card);
        } else {
          // Uložená karta zmizela (smazaná v profilu) → klasický flow.
          _runPaymentSheetFlow(_amount);
        }
      },
      secondaryLabel: tr.tr('payWithAnotherCard'),
      onSecondary: () {
        if (mounted) _runPaymentSheetFlow(_amount);
      },
    );
  }

  /// Chyba Stripe z kartového sheetu (zamítnutí, 3DS, peněženka).
  Future<void> _handleStripeError(StripeException e, {bool wallet = false}) async {
    final lang = t(context).lang;
    final info = PaymentErrorMapper.fromStripeException(e, lang, wallet: wallet);
    // Uživatel jen zavřel Payment Sheet — není to chyba, jen reset.
    if (info.userCancelled) {
      await PaymentPendingMarker.clear(_markerId);
      _setProcessing(false);
      return;
    }
    // Bez kódu karty (výpadek spojení po odeslání) — nevíme, jestli prošla.
    if (info.needsVerification) {
      await _resolveAfterSheetError(e, wallet: wallet);
      return;
    }
    await PaymentPendingMarker.clear(_markerId);
    if (!mounted) return;
    _setProcessing(false);
    if (info.cause == 'amount_too_small') {
      _showProblem(PaymentRefusals.belowMinimum(lang, _flow, _amount));
      return;
    }
    _attempts++;
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    _showError(
      title: info.title,
      message: info.message + _counter,
      buttonLabel: t(context).tr('retry'),
      onButton: () {
        // Rovnou znovu otevři kartový sheet — pole se při otevření čistí
        // (viz CardPaymentSheet), takže špatně zadané číslo jde hned opravit.
        if (mounted) _runPaymentSheetFlow(_amount);
      },
    );
  }

  /// Nejasná chyba po odeslání platby ze sheetu (výjimka pluginu, výpadek
  /// sítě). Rozhodne skutečný stav PaymentIntentu — „nic nestrženo" se smí
  /// říct jen po ověření (port logiky iOS `resolveApplePayFailure`).
  Future<void> _resolveAfterSheetError(Object error, {bool wallet = false}) async {
    debugPrint('[Payment] sheet error, verifying PI: $error');
    final cs = _activeClientSecret;
    final status = cs == null ? null : await StripeService.fetchIntentStatus(cs);
    if (!mounted) return;
    // Stav se nepodařilo zjistit / spojení spadlo → „ověřuje se" řekne pravý
    // důvod (spojení), ne „banka ještě potvrzuje".
    if (status == null || isNetworkError(error)) _netTrouble = true;
    switch (StripeService.outcomeForStatus(status)) {
      case NextActionOutcome.succeeded:
        await _verifyAndComplete();
      case NextActionOutcome.processing:
      case NextActionOutcome.unknown:
        await _awaitProcessingConfirmation();
      case NextActionOutcome.notCompleted:
      case NextActionOutcome.failed:
        await PaymentPendingMarker.clear(_markerId);
        _setProcessing(false);
        _handleGatewayError(error, wallet: wallet);
    }
  }

  /// Ověřeně nezaplaceno, příčina ale není karetní kód (peněženka, plugin).
  void _handleGatewayError(Object error, {bool wallet = false}) {
    _attempts++;
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    final lang = t(context).lang;
    final raw = error.toString();
    // Google Pay / Apple Pay selhání (typicky OR_BIBED_11) — navedeme zákazníka
    // na zaplacení kartou, která funguje vždy, místo nicneříkajícího dumpu.
    final low = raw.toLowerCase();
    final isWallet = wallet ||
        raw.contains('OR_BIBED') ||
        low.contains('google pay') ||
        low.contains('googlepay') ||
        low.contains('wallet') ||
        low.contains('apple pay');
    final info = isWallet
        ? PaymentErrorMapper.walletFailed(lang,
            rawCode: raw.contains('OR_BIBED') ? 'OR_BIBED_11' : null)
        : PaymentErrorMapper.generic(lang);
    _showError(
      title: info.title,
      message: info.message + _counter,
      buttonLabel: t(context).tr('retry'),
      onButton: () {
        // Sheet obsahuje kartu i platformní peněženku — po chybě ho rovnou
        // znovu otevři (s čistým polem), ať má zákazník kde pokračovat.
        if (mounted) _runPaymentSheetFlow(_amount);
      },
    );
  }

  void _handleMaxAttempts() {
    final tr = t(context);
    final edit = _flow == PayFlow.edit || _flow == PayFlow.swap;
    _showError(
      title: tr.tr('paymentFailed'),
      message: tr.tr(edit ? 'psMaxEditBody' : 'psMaxBookingBody'),
      buttonLabel: tr.tr(edit ? 'psBackToReservation' : 'goToReservations'),
      onButton: () {
        if (!mounted) return;
        context.go(edit && _pendingBookingId != null
            ? '/reservations/$_pendingBookingId'
            : Routes.reservations);
      },
      secondaryLabel: tr.tr('psWriteUs'),
      onSecondary: () => openContactUs(context),
      dismissible: false,
    );
  }

  /// Spojení se přerušilo po odeslání platby — ověř ~30 s v DB (5 × 6 s,
  /// každý dotaz s timeoutem). Zaplaceno → úspěch; prokazatelně nezaplaceno
  /// → „nic nestrženo, zkus znovu"; jinak „Platba se ověřuje".
  Future<void> _verifyUncertain() async {
    if (!mounted || _completed) return;
    _setProcessing(true);
    _markVerifying();
    // Nejistý výsledek = přerušené spojení (ztracená odpověď / stav neznámý).
    _netTrouble = true;
    final tr = t(context);
    showMotoGoToast(context,
        icon: '⏳',
        title: tr.tr('psUncertainTitle'),
        message: tr.tr('psUncertainBody'),
        duration: const Duration(seconds: 6));
    await _setMarker(clientSecret: _activeClientSecret);
    final state = await verifyPayment(
      bookingId: _pendingBookingId,
      orderId: _pendingOrderId,
      expectedTotal: _expectedEditTotal,
      intentOnly: _flow == PayFlow.swap,
      attempts: 5,
      interval: const Duration(seconds: 6),
    );
    if (!mounted) return;
    switch (state) {
      case VerifyState.paid:
        _onPaymentSuccess();
      case VerifyState.pending:
        await _goPending();
      case VerifyState.notPaid:
        _setProcessing(false);
        _showError(
          title: tr.tr('psNotPaidTitle'),
          message: tr.tr('psNotPaidRetry'),
          buttonLabel: tr.tr('retry'),
          onButton: _doPayment,
        );
    }
  }

  /// Platbu Stripe přijal / mohla projít, server ji zatím nepotvrdil →
  /// obrazovka „Platba se ověřuje" (ne toast + Rezervace s FAB „Zaplatit").
  /// Neslibuje e-mail, který ještě neodešel.
  Future<void> _goPending() async {
    if (_completed || !mounted) return;
    _completed = true;
    _countdownTimer?.cancel();
    await _setMarker(clientSecret: _activeClientSecret);
    if (!mounted) return;
    _processingNotifier?.state = false;
    ref.read(paymentContextProvider.notifier).state = null;
    ref.invalidate(pendingBookingFabProvider);
    ref.invalidate(reservationsProvider);
    final tr = t(context);
    final id = _pendingBookingId ?? '';
    final edit = _flow == PayFlow.edit || _flow == PayFlow.swap;
    final outcome = edit
        ? pendingEditOutcome(tr,
            bookingId: id,
            expectedTotal: _expectedEditTotal,
            intentOnly: _flow == PayFlow.swap,
            netTrouble: _netTrouble,
            verified: _editSuccessOutcome(tr, Money.czk(_ctx?.amount ?? 0)))
        : pendingBookingOutcome(tr,
            bookingId: id,
            netTrouble: _netTrouble,
            // Obnovená rezervace → děkovačka „znovu potvrzená"; nová rezervace
            // s doprodejem → objednávka doplňků až po ověřeném zaplacení.
            restore: _ctx?.isRestore ?? false,
            upsell: _isNewBooking ? ref.read(bookingUpsellProvider) : const []);
    ref.read(paymentOutcomeProvider.notifier).state = outcome;
    context.go(Routes.paymentResult);
  }

  /// Vypršel čas na zaplacení. Tlačítko „Zaplatit" se zamkne, sheet nejde
  /// zavřít mimo tlačítko (dřív zůstala mrtvá obrazovka s aktivní platbou).
  Future<void> _onTimeout() async {
    if (!mounted || _completed) return;
    final tr = t(context);
    final edit = _flow == PayFlow.edit || _flow == PayFlow.swap;
    // Koncept rezervace bez běžící platby hned zruš (motorka se uvolní;
    // cron by ho zrušil stejně) — text pak říká pravdu.
    final bid = _pendingBookingId;
    if (!edit && bid != null && !await PaymentPendingMarker.isPending(bid)) {
      try {
        await cancelPendingBooking(bid,
            reason: 'Čas na zaplacení v appce vypršel');
      } catch (_) {/* cron rezervaci zruší sám */}
      if (mounted) ref.invalidate(pendingBookingFabProvider);
    }
    if (!mounted) return;
    final moto = ref.read(bookingMotoProvider);
    _showError(
      title: tr.tr('paymentExpired'),
      message: tr.tr(edit ? 'psExpiredEditBody' : 'psExpiredBookingBody'),
      buttonLabel: tr.tr(edit ? 'psOpenReservation' : 'psPickAgain'),
      onButton: () {
        if (!mounted) return;
        if (edit) {
          context.go(bid != null ? '/reservations/$bid' : Routes.reservations);
        } else {
          context.go(moto != null ? '/moto/${moto.id}' : Routes.search);
        }
      },
      dismissible: false,
    );
  }

  /// Šipka zpět / systémové „zpět". Během platby jen po potvrzení — odchod
  /// pak výsledek nezahodí (značka → FAB „Platba se ověřuje", ne „Zaplatit").
  Future<void> _onBack() async {
    if (_processing && _completed) {
      // Zaplaceno, dopisuje se změna (výměna motorky) — dokončí ji i server.
      if (!await confirmLeaveRunningPayment(context)) return;
      if (mounted) context.go(Routes.reservations);
      return;
    }
    if (_processing && _submitted) {
      if (!await confirmLeaveRunningPayment(context)) return;
      await _setMarker(clientSecret: _activeClientSecret);
      if (!mounted) return;
      ref.invalidate(pendingBookingFabProvider);
      context.go(Routes.reservations);
      return;
    }
    // Nic ještě neodešlo (zakládá se rezervace / platba) → odchod nic
    // nestrhne; žádná značka „ověřuje se", žádný falešný stav.
    if (mounted) context.backOr(_backFallback);
  }

  /// Rezervaci (koncept) se nepodařilo vytvořit — proč a co dál.
  void _showDraftFailure() {
    final tr = t(context);
    final draft = ref.read(bookingDraftProvider);
    String fmt(DateTime? d) => d == null ? '–' : '${d.day}. ${d.month}. ${d.year}';
    switch (_draftKind) {
      case _DraftKind.motoTaken:
        _showError(
          title: tr.tr('psMotoTakenTitle'),
          message: tr
              .tr('psMotoTakenBody')
              .replaceAll('{start}', fmt(draft.startDate))
              .replaceAll('{end}', fmt(draft.endDate)),
          buttonLabel: tr.tr('psChangeDates'),
          onButton: () => context.backOr(Routes.booking),
          secondaryLabel: tr.tr('psOtherMoto'),
          onSecondary: () => context.go(Routes.search),
        );
      case _DraftKind.trailerTaken:
        _showError(
          title: tr.tr('bookingCreateFailed'),
          message: tr.tr('swap.trailerOccupied'),
          buttonLabel: tr.tr('psChangeDates'),
          onButton: () => context.backOr(Routes.booking),
        );
      case _DraftKind.network:
        _showError(
          title: tr.tr('bookingCreateFailed'),
          message: tr.tr('psDraftNetBody'),
          buttonLabel: tr.tr('retry'),
          onButton: _doPayment,
        );
      case _DraftKind.auth:
        // Rezervace ještě nevznikla → v Rezervacích nic není (ne psAuthBooking).
        _showError(
          title: PaymentErrorMapper.text(tr.lang, 'authExpiredTitle'),
          message: tr.tr('fxDraftAuthBody'),
          buttonLabel: tr.tr('login'),
          onButton: () => signInAgain(context),
        );
      case _DraftKind.input:
        // Chybí termín / motorka / údaje profilu — oprava je ve formuláři.
        _showError(
          title: tr.tr('bookingCreateFailed'),
          message: _draftError ?? tr.tr('psDraftUnknownBody'),
          buttonLabel: tr.tr('psEditBooking'),
          onButton: () => context.backOr(Routes.booking),
        );
      case _DraftKind.unknown:
        _showError(
          title: tr.tr('bookingCreateFailed'),
          message: _draftError ?? tr.tr('psDraftUnknownBody'),
          buttonLabel: tr.tr('retry'),
          onButton: _doPayment,
          secondaryLabel: tr.tr('psWriteUs'),
          onSecondary: () => openContactUs(context),
        );
    }
  }
}
