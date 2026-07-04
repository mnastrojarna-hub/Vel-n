import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import 'routes_model.dart';

/// Hvězdičkové hodnocení bodu zájmu. Každý přihlášený uživatel může dát právě
/// jedno hodnocení (1–5), které lze kdykoli změnit. Ukazuje průměr + počet
/// hodnocení a vlastní hodnocení. Zápis přes RPC `rate_poi`, čtení přes
/// `poi_rating_summary` (route_poi i user_poi).
class PoiRatingBar extends StatefulWidget {
  final RoutePoi poi;
  const PoiRatingBar({super.key, required this.poi});

  @override
  State<PoiRatingBar> createState() => _PoiRatingBarState();
}

class _PoiRatingBarState extends State<PoiRatingBar> {
  double? _avg;
  int _count = 0;
  int? _mine;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _avg = widget.poi.avgRating;
    _count = widget.poi.ratingCount;
    _load();
  }

  Map<String, dynamic> get _args => widget.poi.isCatalogPoi
      ? {'p_route_poi_id': null, 'p_user_poi_id': null, 'p_poi_id': widget.poi.id}
      : widget.poi.isUserPoi
          ? {'p_route_poi_id': null, 'p_user_poi_id': widget.poi.id}
          : {'p_route_poi_id': widget.poi.id, 'p_user_poi_id': null};

  // Postgres numeric chodí přes PostgREST jako String ("4.5") → parsuj robustně.
  static double? _toD(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toI(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<void> _load() async {
    try {
      final res = await MotoGoSupabase.client.rpc('poi_rating_summary', params: _args);
      if (!mounted) return;
      final row = (res is List && res.isNotEmpty) ? res.first : res;
      if (row is Map) {
        setState(() {
          _avg = _toD(row['avg_rating']);
          _count = _toI(row['rating_count']) ?? 0;
          _mine = _toI(row['my_rating']);
        });
      }
    } catch (_) {/* ponech iniciální hodnoty */}
  }

  Future<void> _rate(int star) async {
    if (MotoGoSupabase.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context).tr('poiRateLogin'))),
      );
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _mine = star; // optimisticky
    });
    try {
      await MotoGoSupabase.client.rpc('rate_poi', params: {..._args, 'p_rating': star});
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hodnota pro vykreslení hvězd: moje hodnocení má přednost, jinak průměr.
    final shown = (_mine ?? _avg ?? 0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => _rate(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    shown >= i ? Icons.star : (shown >= i - 0.5 ? Icons.star_half : Icons.star_border),
                    size: 30,
                    color: const Color(0xFFF5B301),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            if (_count > 0)
              Text(
                '${(_avg ?? 0).toStringAsFixed(1)} · $_count',
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w800,
                  color: MotoGoColors.g600,
                  decoration: TextDecoration.none,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _mine != null
              ? t(context).tr('poiRateYours')
              : (_count == 0 ? t(context).tr('poiNoRatings') : t(context).tr('poiRateHint')),
          style: const TextStyle(
            fontSize: MotoGoTypo.sizeMd,
            fontWeight: MotoGoTypo.w600,
            color: MotoGoColors.g500,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
