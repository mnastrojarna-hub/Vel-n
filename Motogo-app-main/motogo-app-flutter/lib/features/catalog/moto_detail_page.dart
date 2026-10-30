import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/net_image.dart';
import '../../core/router.dart';
import '../booking/booking_entry.dart';
import '../booking/booking_models.dart' show BookingDraft;
import '../booking/booking_provider.dart' show bookingDraftProvider;
import 'catalog_provider.dart';
import 'moto_model.dart';
import 'widgets/availability_calendar.dart';
import 'widgets/fullscreen_gallery.dart';
import 'widgets/manual_card.dart';
import 'widgets/moto_video_player.dart';
import 'widgets/price_footer.dart';
import 'widgets/pricing_table.dart';
import 'widgets/specs_section.dart';
import 'widgets/validation_banner.dart';
import '../../core/date_days.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../../core/v2/widgets/mg_buttons.dart';
import 'v2/detail/detail_dates_carry_v2.dart';
import 'v2/detail/detail_states_v2.dart';
import 'v2/detail/moto_detail_view_v2.dart';

/// Detail content for a single motorcycle.
/// Used inside the pager (MotoDetailScreen) — one page per motorcycle.
class MotoDetailPage extends ConsumerStatefulWidget {
  final String motoId;

  /// When true, the page shows its own back button (for standalone use).
  /// When false, the parent pager handles navigation.
  final bool showBackButton;

  const MotoDetailPage({
    super.key,
    required this.motoId,
    this.showBackButton = false,
  });

  @override
  ConsumerState<MotoDetailPage> createState() => _MotoDetailPageState();
}

class _MotoDetailPageState extends ConsumerState<MotoDetailPage> {
  int _imageIndex = 0;
  DateTime? _selStart;
  DateTime? _selEnd;
  late PageController _pageCtrl;
  bool _calendarExpanded = true;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // v2: termín rozpracované rezervace TÉTO motorky má přednost (2026-10-22).
      final (s, e) = detailStartDates(context, ref, widget.motoId);
      if (s != null && e != null) {
        setState(() {
          _selStart = s;
          _selEnd = e;
          _calendarExpanded = false;
        });
      }
    });
  }

  /// v2: termín změněný ve formuláři („Změnit“) se propíše do detailu pod ním.
  void _followDraftDates(BookingDraft? prev, BookingDraft next) {
    final r = detailFollowDraft(prev, next, widget.motoId, _selStart, _selEnd);
    if (r != null) _pickRange(r.$1, r.$2);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

  // Obsluha sdílená starým i v2 vzhledem (těla beze změny, jen vytažená
  // z inline closur, aby obě větve volaly totéž).
  void _onImageChanged(int i) => setState(() => _imageIndex = i);

  void _openGallery(BuildContext ctx, List<String> images) => FullscreenGallery.open(
        ctx,
        images: images,
        initialIndex: _imageIndex,
      );

  void _toggleCalendar() =>
      setState(() => _calendarExpanded = !_calendarExpanded);

  void _expandCalendar() => setState(() => _calendarExpanded = true);

  void _onCalendarRange(DateTime s, DateTime e) => setState(() {
        _selStart = s;
        _selEnd = e;
        _calendarExpanded = false;
      });

  void _onCalendarStart(DateTime date) => setState(() {
        _selStart = date;
        _selEnd = null;
      });

  void _onCalendarReset() => setState(() {
        _selStart = null;
        _selEnd = null;
      });

  /// v2: termín vybraný (nebo zrušený) v detailu platí pro celý katalog —
  /// další motorky v pageru, seznam Motorek, pilulka na Domů (stejný zápis
  /// jako výběr termínu v Motorkách; majitel 2026-10-22 „nic nevyplňovat
  /// dvakrát“). Jen začátek (jednodenní výběr) zůstává v detailu.
  void _pickRange(DateTime s, DateTime e) {
    _onCalendarRange(s, e);
    detailShareRange(ref, s, e);
  }

  void _pickReset() {
    _onCalendarReset();
    detailShareReset(ref);
  }

  /// REZERVOVAT — jen začátek = jednodenní rezervace (PM-3).
  void _reserve(BuildContext ctx, Motorcycle moto) =>
      startBookingFromSelection(ctx, ref, moto, _selStart!, _selEnd ?? _selStart!);

  @override
  Widget build(BuildContext context) {
    if (MgV2.on(context)) ref.listen<BookingDraft>(bookingDraftProvider, _followDraftDates);
    final motosAsync = ref.watch(motorcyclesProvider);
    final bookedAsync = ref.watch(bookedDatesProvider(widget.motoId));

    return motosAsync.when(
      data: (motos) {
        final moto = motos.where((m) => m.id == widget.motoId).firstOrNull;
        if (moto == null) {
          // Motorka už není v nabídce (vyřazená / stažená, starý odkaz
          // z rezervace) → proč + cesta dál, ne holý text bez akce.
          final tr = t(context);
          if (MgV2.on(context)) {
            return _stateFrame(MgErrorView(
              what: tr.tr('r3MotoGoneTitle'),
              message: tr.tr('r3MotoGoneBody'),
              contact: false,
              extra: [
                MgBtnInk(
                  label: tr.tr('r3PickOtherMoto'),
                  onTap: () => context.go(Routes.search),
                ),
              ],
            ));
          }
          return _stateFrame(MgErrorView(
            what: tr.tr('r3MotoGoneTitle'),
            message: tr.tr('r3MotoGoneBody'),
            contact: false,
            extra: [
              ElevatedButton(
                onPressed: () => context.go(Routes.search),
                child: Text(tr.tr('r3PickOtherMoto')),
              ),
            ],
          ));
        }
        return _buildDetail(context, moto, bookedAsync);
      },
      // Po 15 s „trvá to déle" + Zkusit znovu / Zpět (nikdy holý spinner);
      // v2: kostra fotky a listu detailu, stejné akce.
      loading: () => _stateFrame(MgV2.on(context)
          ? DetailLoadingV2(onRetry: () => ref.invalidate(motorcyclesProvider), onBack: _back)
          : MgLoadingView(
              onRetry: () => ref.invalidate(motorcyclesProvider),
              onBack: _back,
            )),
      // Důvod + Zkusit znovu / Zpět, nikdy syrová výjimka (v2: jedna motorka).
      error: (e, _) => _stateFrame(MgErrorView(
        error: e,
        what: t(context).tr(MgV2.on(context) ? 'v2DetLoadFail' : 'eoMotosLoadFail'),
        onRetry: () => ref.invalidate(motorcyclesProvider),
        onBack: _back,
      )),
    );
  }

  /// Zpět ze samostatného detailu (rezervace, pobočka, `context.go` po
  /// vypršené platbě) — bez historie do katalogu.
  void _back() => context.backOr(Routes.search);

  /// Stav bez dat: v samostatném režimu s hlavičkou a šipkou zpět (šipka
  /// detailu se kreslí až s daty); v pageru ji kreslí MotoDetailScreen.
  Widget _stateFrame(Widget child) => widget.showBackButton
      ? MgStateScaffold(onBack: _back, child: child)
      : child;

  Widget _buildDetail(
    BuildContext ctx,
    Motorcycle moto,
    AsyncValue<List<BookedDateRange>> bookedAsync,
  ) {
    final images = moto.images.isNotEmpty
        ? moto.images
        : (moto.imageUrl != null ? [moto.imageUrl!] : <String>[]);
    final branchInfo = [moto.branchName, moto.branchCity]
        .where((e) => e != null)
        .join(', ');
    final hasDates = _selStart != null && _selEnd != null;
    final dayCount =
        hasDates ? calendarDaysInclusive(_selStart!, _selEnd!) : 0;
    final totalPrice = hasDates && moto.prices != null
        ? moto.prices!.totalForRange(_selStart!, _selEnd!)
        : 0.0;

    // v2 vzhled (kill-switch app_v2_ui): stejný stav i obsluha, jen jiný strom.
    if (MgV2.on(ctx)) {
      // Přenesený termín s obsazeným dnem: kalendář otevřený, varování,
      // REZERVOVAT vypnuté (jinak by to odmítla až platba).
      final busy = detailRangeBusy(bookedAsync, _selStart, _selEnd);
      return MotoDetailV2View(
        moto: moto,
        images: images,
        branchInfo: branchInfo,
        imageIndex: _imageIndex,
        pageCtrl: _pageCtrl,
        onImageChanged: _onImageChanged,
        onOpenGallery: images.isNotEmpty ? () => _openGallery(ctx, images) : null,
        onBack: widget.showBackButton ? _back : null,
        selStart: _selStart,
        selEnd: _selEnd,
        hasDates: hasDates,
        dayCount: dayCount,
        totalPrice: totalPrice,
        calendarExpanded: _calendarExpanded || busy,
        onToggleCalendar: _toggleCalendar,
        onRangeSelected: _pickRange,
        onStartSelected: _onCalendarStart,
        onReset: _pickReset,
        bookedAsync: bookedAsync,
        busy: busy,
        onPickDates: _expandCalendar,
        onReserve: _selStart != null && !busy ? () => _reserve(ctx, moto) : null,
      );
    }

    return CustomScrollView(
      slivers: [
        // === IMAGE CAROUSEL ===
        SliverToBoxAdapter(child: _buildImageCarousel(ctx, images, moto, branchInfo)),

        // === VIDEO(A) — přehrávají se až po otevření detailu (jen pokud existují) ===
        if (moto.videos.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MotoVideoPlayer(
                key: ValueKey('motovid-${moto.id}'),
                urls: moto.videos,
              ),
            ),
          ),

        // === AVAILABILITY BADGE — only when confirmed available today ===
        if (moto.availableToday == true)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                Icon(Icons.check_circle, size: 18, color: MotoGoColors.greenDark),
                const SizedBox(width: 6),
                Text(
                  t(ctx).tr('detailAvailableNow'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.greenDark,
                  ),
                ),
              ]),
            ),
          ),

        // === BRANCH INFO ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${t(ctx).tr('detailBranchLabel')}$branchInfo',
              style: const TextStyle(fontSize: 13, color: MotoGoColors.g600),
            ),
          ),
        ),

        // === DESCRIPTION === (plain text — HTML markup stripped, lokalizovaný)
        if (moto.descriptionPlainFor(t(ctx).lang) != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                moto.descriptionPlainFor(t(ctx).lang)!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: MotoGoColors.g600,
                ),
              ),
            ),
          ),

        // === SPECS GRID ===
        if (moto.specList(t(context).tr).isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SpecsSection(specs: moto.specList(t(context).tr)),
            ),
          ),

        // === PRICING TABLE ===
        if (moto.prices != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PricingTable(prices: moto.prices!),
            ),
          ),

        // === CALENDAR ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildCalendar(ctx, bookedAsync, hasDates, dayCount),
          ),
        ),

        // === MANUAL PDF ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ManualCard(moto: moto),
          ),
        ),

        // === PRICE CARD ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PriceFooter(
              prices: moto.prices,
              totalPrice: totalPrice,
              dayCount: dayCount,
            ),
          ),
        ),

        // === VALIDATION BANNER ===
        if (hasDates)
          SliverToBoxAdapter(
            child: ValidationBanner(
              moto: moto,
              startDate: _selStart!,
              endDate: _selEnd!,
            ),
          ),

        // === CTA BUTTON ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildCtaButton(ctx, moto, hasDates),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
        ),
      ],
    );
  }

  Widget _buildImageCarousel(
    BuildContext ctx,
    List<String> images,
    Motorcycle moto,
    String branchInfo,
  ) {
    final hasMultiple = images.length > 1;

    return Stack(
      children: [
        GestureDetector(
          onTap: images.isNotEmpty ? () => _openGallery(ctx, images) : null,
          child: SizedBox(
            height: 260,
            child: hasMultiple
                // Multi-image carousel – swipeable PageView
                ? PageView.builder(
                    controller: _pageCtrl,
                    itemCount: images.length,
                    onPageChanged: _onImageChanged,
                    itemBuilder: (_, i) => ColoredBox(
                      color: MotoGoColors.g100,
                      child: MgImage(
                        images[i],
                        thumbWidth: 1000,
                        // contain = celá fotka viditelná (jako ve velíně)
                        fit: BoxFit.contain,
                        width: double.infinity,
                        placeholder: Container(color: MotoGoColors.g200),
                        error: Container(
                          color: MotoGoColors.g200,
                          child: const Icon(Icons.motorcycle,
                              size: 48, color: MotoGoColors.g400),
                        ),
                      ),
                    ),
                  )
                // Single image (or none) – no PageView so horizontal gestures
                // propagate to the outer motorcycle pager.
                : images.isNotEmpty
                    ? ColoredBox(
                        color: MotoGoColors.g100,
                        child: MgImage(
                          images.first,
                          thumbWidth: 1000,
                          // contain = celá fotka viditelná (jako ve velíně)
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: 260,
                          placeholder: Container(color: MotoGoColors.g200),
                          error: Container(
                            color: MotoGoColors.g200,
                            child: const Icon(Icons.motorcycle,
                                size: 48, color: MotoGoColors.g400),
                          ),
                        ),
                      )
                    : Container(
                        color: MotoGoColors.g200,
                        child: const Icon(Icons.motorcycle,
                            size: 48, color: MotoGoColors.g400),
                      ),
          ),
        ),
        // Gradient
        Positioned(
          bottom: 0, left: 0, right: 0, height: 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  MotoGoColors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),
        // Name + branch overlay
        Positioned(
          bottom: 16, left: 16, right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                moto.model,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              if (branchInfo.isNotEmpty)
                Text(
                  branchInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
        // Back button (only in standalone mode)
        if (widget.showBackButton)
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            left: 12,
            child: MgBackTap(
              // Detail lze otevřít i deep-linkem/notifikací → v zásobníku není
              // co popnout a `pop()` by hodil „GoError: nothing to pop". Fallback
              // na katalog.
              onTap: _back,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back,
                    size: 20, color: Colors.black),
              ),
            ),
          ),
        // Photo counter badge (always visible when there are images)
        if (images.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MotoGoColors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(
                    '${_imageIndex + 1} / ${images.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Dots
        if (hasMultiple)
          Positioned(
            bottom: 4, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                images.length,
                (i) => Container(
                  width: i == _imageIndex ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == _imageIndex
                        ? MotoGoColors.green
                        : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendar(
    BuildContext ctx,
    AsyncValue<List<BookedDateRange>> bookedAsync,
    bool hasDates,
    int dayCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggleCalendar,
            child: Row(children: [
              const Icon(Icons.calendar_month,
                  size: 16, color: MotoGoColors.dark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t(ctx).tr('detailAvailabilityTitle'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.dark,
                  ),
                ),
              ),
              Icon(
                _calendarExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: MotoGoColors.g400,
              ),
            ]),
          ),
          // Collapsed date summary
          if (!_calendarExpanded && hasDates) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            t(ctx).tr('detailPickupLabel'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MotoGoColors.g600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(_selStart!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.black,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        Flexible(
                          child: Text(
                            t(ctx).tr('detailReturnLabel'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MotoGoColors.g600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(_selEnd!),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.black,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                Column(children: [
                  Text(
                    '$dayCount',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: MotoGoColors.greenDarker,
                    ),
                  ),
                  Text(
                    dayCount == 1
                        ? t(ctx).tr('day1')
                        : dayCount < 5
                            ? t(ctx).tr('days24')
                            : t(ctx).tr('days5'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.greenDarker,
                    ),
                  ),
                ]),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _expandCalendar,
                  child: Text(
                    t(ctx).tr('detailEditBtn'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: MotoGoColors.greenDark,
                    ),
                  ),
                ),
              ]),
            ),
          ],
          // Expanded calendar
          if (_calendarExpanded) ...[
            const SizedBox(height: 4),
            Text(
              t(ctx).tr('searchSingleDayHint'),
              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
            ),
            const SizedBox(height: 8),
            AvailabilityCalendar(
              bookedDates: bookedAsync.valueOrNull ?? [],
              selectedStart: _selStart,
              selectedEnd: _selEnd,
              onRangeSelected: _onCalendarRange,
              onStartSelected: _onCalendarStart,
              onReset: _onCalendarReset,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCtaButton(
    BuildContext ctx,
    Motorcycle moto,
    bool hasDates,
  ) {
    // Button active when at least start date is selected.
    // If only start is picked, clicking confirms single-day booking.
    final canProceed = _selStart != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!canProceed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              t(ctx).tr('detailSelectDatesHint'),
              style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
            ),
          ),
        SizedBox(
          height: 52,
          child: PressableScale(
            enabled: canProceed,
            child: ShimmerSweep(
            borderRadius: BorderRadius.circular(50),
            child: ElevatedButton(
            onPressed: canProceed
                ? () => _reserve(ctx, moto)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.black,
          disabledBackgroundColor: MotoGoColors.g200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t(ctx).tr('detailReserveBtn'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
      ),
      ),
    ),
      ],
    );
  }
}
