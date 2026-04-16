import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/router.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import 'catalog_provider.dart';
import 'moto_model.dart';
import 'widgets/availability_calendar.dart';
import 'widgets/fullscreen_gallery.dart';
import 'widgets/manual_card.dart';
import 'widgets/price_footer.dart';
import 'widgets/pricing_table.dart';
import 'widgets/specs_section.dart';
import 'widgets/validation_banner.dart';

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
      final filter = ref.read(catalogFilterProvider);
      if (filter.startDate != null && filter.endDate != null) {
        setState(() {
          _selStart = filter.startDate;
          _selEnd = filter.endDate;
          _calendarExpanded = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);
    final bookedAsync = ref.watch(bookedDatesProvider(widget.motoId));

    return motosAsync.when(
      data: (motos) {
        final moto = motos.where((m) => m.id == widget.motoId).firstOrNull;
        if (moto == null) {
          return Center(child: Text(t(context).tr('detailNotFoundMessage')));
        }
        return _buildDetail(context, moto, bookedAsync);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: MotoGoColors.green),
      ),
      error: (e, _) => Center(
        child: Text('${t(context).tr('catalogErrorPrefix')}$e'),
      ),
    );
  }

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
        hasDates ? _selEnd!.difference(_selStart!).inDays + 1 : 0;
    final totalPrice = hasDates && moto.prices != null
        ? moto.prices!.totalForRange(_selStart!, _selEnd!)
        : 0.0;

    return CustomScrollView(
      slivers: [
        // === IMAGE CAROUSEL ===
        SliverToBoxAdapter(child: _buildImageCarousel(ctx, images, moto, branchInfo)),

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

        // === DESCRIPTION ===
        if (moto.description != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                moto.description!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: MotoGoColors.g600,
                ),
              ),
            ),
          ),

        // === SPECS GRID ===
        if (moto.specList.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SpecsSection(specs: moto.specList),
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
          onTap: images.isNotEmpty
              ? () => FullscreenGallery.open(
                    ctx,
                    images: images,
                    initialIndex: _imageIndex,
                  )
              : null,
          child: SizedBox(
            height: 260,
            child: hasMultiple
                // Multi-image carousel – swipeable PageView
                ? PageView.builder(
                    controller: _pageCtrl,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _imageIndex = i),
                    itemBuilder: (_, i) => CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) =>
                          Container(color: MotoGoColors.g200),
                      errorWidget: (_, __, ___) => Container(
                        color: MotoGoColors.g200,
                        child: const Icon(Icons.motorcycle,
                            size: 48, color: MotoGoColors.g400),
                      ),
                    ),
                  )
                // Single image (or none) – no PageView so horizontal gestures
                // propagate to the outer motorcycle pager.
                : images.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: images.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 260,
                        placeholder: (_, __) =>
                            Container(color: MotoGoColors.g200),
                        errorWidget: (_, __, ___) => Container(
                          color: MotoGoColors.g200,
                          child: const Icon(Icons.motorcycle,
                              size: 48, color: MotoGoColors.g400),
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              if (branchInfo.isNotEmpty)
                Text(
                  branchInfo,
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
            child: GestureDetector(
              onTap: () => ctx.pop(),
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
            onTap: () =>
                setState(() => _calendarExpanded = !_calendarExpanded),
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
                        Text(
                          t(ctx).tr('detailPickupLabel'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MotoGoColors.g600,
                          ),
                        ),
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
                        Text(
                          t(ctx).tr('detailReturnLabel'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MotoGoColors.g600,
                          ),
                        ),
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
                  onTap: () => setState(() => _calendarExpanded = true),
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
              onRangeSelected: (s, e) => setState(() {
                _selStart = s;
                _selEnd = e;
                _calendarExpanded = false;
              }),
              onStartSelected: (date) => setState(() {
                _selStart = date;
                _selEnd = null;
              }),
              onReset: () => setState(() {
                _selStart = null;
                _selEnd = null;
              }),
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
          child: ElevatedButton(
            onPressed: canProceed
                ? () {
                final effectiveEnd = _selEnd ?? _selStart!;
                ref.read(bookingMotoProvider.notifier).state = moto;
                ref.read(bookingDraftProvider.notifier).state = BookingDraft(
                  motoId: moto.id,
                  motoName: moto.model,
                  motoImage: moto.displayImage,
                  startDate: _selStart,
                  endDate: effectiveEnd,
                );
                ctx.push(Routes.booking);
              }
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
      ],
    );
  }
}
