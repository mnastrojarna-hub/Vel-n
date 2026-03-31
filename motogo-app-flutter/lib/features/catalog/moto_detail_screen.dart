import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import 'catalog_provider.dart';
import 'moto_model.dart';
import 'widgets/availability_calendar.dart';

/// Motorcycle detail — mirrors s-detail from templates-screens-booking.js.
/// Image carousel, specs grid, pricing card, availability calendar.
class MotoDetailScreen extends ConsumerStatefulWidget {
  final String motoId;
  const MotoDetailScreen({super.key, required this.motoId});

  @override
  ConsumerState<MotoDetailScreen> createState() => _MotoDetailScreenState();
}

class _MotoDetailScreenState extends ConsumerState<MotoDetailScreen> {
  int _imageIndex = 0;
  DateTime? _selectedStart;
  DateTime? _selectedEnd;

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(motorcyclesProvider);
    final bookedAsync = ref.watch(bookedDatesProvider(widget.motoId));

    return motosAsync.when(
      data: (motos) {
        final moto = motos.where((m) => m.id == widget.motoId).firstOrNull;
        if (moto == null) {
          return Scaffold(
            backgroundColor: MotoGoColors.bg,
            appBar: AppBar(title: const Text('Motorka nenalezena')),
            body: const Center(child: Text('Motorka neexistuje')),
          );
        }
        return _buildDetail(context, moto, bookedAsync);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Chyba: $e')),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, Motorcycle moto, AsyncValue<List<BookedDateRange>> bookedAsync) {
    final images = moto.images.isNotEmpty ? moto.images : [moto.displayImage];
    final totalPrice = (_selectedStart != null && _selectedEnd != null && moto.prices != null)
        ? moto.prices!.totalForRange(_selectedStart!, _selectedEnd!)
        : null;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image carousel
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      height: 280,
                      child: PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        itemBuilder: (_, i) => CachedNetworkImage(
                          imageUrl: images[i],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => Container(color: MotoGoColors.g200),
                          errorWidget: (_, __, ___) => Container(
                            color: MotoGoColors.g200,
                            child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 48))),
                          ),
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
                            colors: [Colors.transparent, MotoGoColors.black.withValues(alpha: 0.9)],
                          ),
                        ),
                      ),
                    ),
                    // Name
                    Positioned(
                      bottom: 16, left: 16, right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(moto.model, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                          if (moto.branchName != null)
                            Text(
                              '${moto.branchName}${moto.branchCity != null ? ', ${moto.branchCity}' : ''}',
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                            ),
                        ],
                      ),
                    ),
                    // Dots
                    if (images.length > 1)
                      Positioned(
                        bottom: 8, left: 0, right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(images.length, (i) => Container(
                            width: i == _imageIndex ? 16 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i == _imageIndex ? MotoGoColors.green : Colors.white54,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )),
                        ),
                      ),
                    // Back button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                      ),
                    ),
                    // License badge
                    if (moto.licenseRequired != null)
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: MotoGoColors.dark.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
                          child: Text('ŘP ${moto.licenseRequired}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.green)),
                        ),
                      ),
                  ],
                ),
              ),

              // Description
              if (moto.description != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(moto.description!, style: const TextStyle(fontSize: 13, height: 1.6, color: MotoGoColors.g600)),
                  ),
                ),

              // Specs grid
              if (moto.specList.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _SpecGrid(specs: moto.specList),
                  ),
                ),

              // Pricing card
              if (moto.prices != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _PricingCard(prices: moto.prices!),
                  ),
                ),

              // Calendar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                      boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Dostupnost – vyberte termín', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                        const SizedBox(height: 10),
                        AvailabilityCalendar(
                          bookedDates: bookedAsync.valueOrNull ?? [],
                          selectedStart: _selectedStart,
                          selectedEnd: _selectedEnd,
                          onRangeSelected: (s, e) => setState(() { _selectedStart = s; _selectedEnd = e; }),
                        ),
                        if (totalPrice != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Celkem:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                                Text('${totalPrice.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // Sticky CTA button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: ElevatedButton(
                onPressed: () => context.push(Routes.booking),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(totalPrice != null
                    ? 'Rezervovat · ${totalPrice.toStringAsFixed(0)} Kč →'
                    : 'Rezervovat motorku →'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecGrid extends StatelessWidget {
  final List<MapEntry<String, String>> specs;
  const _SpecGrid({required this.specs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Technická specifikace', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 10),
          ...specs.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(s.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400))),
                Expanded(flex: 3, child: Text(s.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final DayPrices prices;
  const _PricingCard({required this.prices});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ceník', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              Text('od ${prices.cheapest.toStringAsFixed(0)} Kč/den', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final price = prices.asList[i];
              return Expanded(
                child: Column(
                  children: [
                    Text(DayPrices.dayLabels[i], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
                    const SizedBox(height: 4),
                    Text(
                      price > 0 ? '${price.toStringAsFixed(0)}' : '–',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.black),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          const Text('Cena bez DPH, nejsme plátci', style: TextStyle(fontSize: 9, color: MotoGoColors.g400)),
        ],
      ),
    );
  }
}
