import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import 'routes_model.dart';
import 'route_reviews.dart' show routeReviewTile, routeStars;

double? _toD(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int _toI(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

/// Cíl recenze bodu zájmu podle jeho typu — právě jeden z parametrů je nenull:
/// katalog → `p_poi_id`, uživatelský → `p_user_poi_id`, jinak `p_route_poi_id`.
/// Stejná logika jako v `PoiRatingBar`.
Map<String, dynamic> poiReviewTarget(RoutePoi poi) => poi.isCatalogPoi
    ? {'p_route_poi_id': null, 'p_user_poi_id': null, 'p_poi_id': poi.id}
    : poi.isUserPoi
        ? {'p_route_poi_id': null, 'p_user_poi_id': poi.id, 'p_poi_id': null}
        : {'p_route_poi_id': poi.id, 'p_user_poi_id': null, 'p_poi_id': null};

/// Recenze bodu zájmu — hvězdičkové hodnocení + textová recenze + fotky. Každý
/// přihlášený uživatel může bod jednou ohodnotit (lze upravit). Čtení přes RPC
/// `get_poi_reviews`, zápis přes `submit_poi_review`, mazání `delete_poi_review`,
/// foto do bucketu `media` pod prefixem `poi-reviews/`. Sdílí vizuál recenzí tras.
class PoiReviewsSection extends StatefulWidget {
  /// Identifikace cíle (`p_route_poi_id` / `p_user_poi_id` / `p_poi_id`) —
  /// vytvoř přes [poiReviewTarget].
  final Map<String, dynamic> target;
  const PoiReviewsSection({super.key, required this.target});

  @override
  State<PoiReviewsSection> createState() => _PoiReviewsSectionState();
}

class _PoiReviewsSectionState extends State<PoiReviewsSection> {
  double? _avg;
  int _count = 0;
  Map<String, dynamic>? _my;
  List<Map<String, dynamic>> _reviews = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await MotoGoSupabase.client.rpc('get_poi_reviews', params: widget.target);
      if (!mounted) return;
      if (res is Map) {
        setState(() {
          _avg = _toD(res['avg']);
          _count = _toI(res['count']);
          _my = res['my'] is Map ? Map<String, dynamic>.from(res['my']) : null;
          _reviews = (res['reviews'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEditor() {
    if (MotoGoSupabase.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeReviewLogin'))));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PoiReviewEditor(
        target: widget.target,
        existing: _my,
        onSaved: () { Navigator.of(context).maybePop(); _load(); },
      ),
    );
  }

  Future<void> _delete() async {
    try {
      await MotoGoSupabase.client.rpc('delete_poi_review', params: widget.target);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.greenDark))));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle(t(context).tr('routeReviewsHeader')),
            const Spacer(),
            if (_count > 0) ...[
              routeStars(_avg ?? 0, size: 16),
              const SizedBox(width: 6),
              Text('${(_avg ?? 0).toStringAsFixed(1)} · $_count ${t(context).tr('routeReviewCountSuffix')}',
                  style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w700, color: MotoGoColors.g600, decoration: TextDecoration.none)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // CTA napsat / upravit recenzi
        PressableScale(
          pressedScale: 0.97,
          onTap: _openEditor,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              border: Border.all(color: MotoGoColors.green, width: 1.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_my != null ? Icons.edit : Icons.rate_review, size: 18, color: MotoGoColors.greenDarker),
                const SizedBox(width: 8),
                Text(_my != null ? t(context).tr('routeReviewEdit') : t(context).tr('routeReviewAdd'),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800, color: MotoGoColors.greenDarker, decoration: TextDecoration.none)),
              ],
            ),
          ),
        ),
        if (_my != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _delete,
              child: Text(t(context).tr('routeReviewDelete'),
                  style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w700, color: Color(0xFFD93636))),
            ),
          ),
        const SizedBox(height: 6),
        if (_reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(t(context).tr('routeReviewsNone'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w600, color: MotoGoColors.g500, decoration: TextDecoration.none)),
          )
        else
          ..._reviews.map((r) => routeReviewTile(context, r)),
      ],
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900, color: MotoGoColors.black, decoration: TextDecoration.none));
}

/// Editor recenze bodu zájmu (bottom sheet) — hvězdy, text, fotky.
class _PoiReviewEditor extends StatefulWidget {
  final Map<String, dynamic> target;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _PoiReviewEditor({required this.target, required this.existing, required this.onSaved});

  @override
  State<_PoiReviewEditor> createState() => _PoiReviewEditorState();
}

class _PoiReviewEditorState extends State<_PoiReviewEditor> {
  late int _rating;
  late final TextEditingController _txt;
  late List<String> _photos; // existující URL
  final List<XFile> _newPhotos = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _rating = (e?['rating'] is num) ? (e!['rating'] as num).toInt() : 0;
    _txt = TextEditingController(text: e?['review_text']?.toString() ?? '');
    _photos = (e?['photos'] as List? ?? const []).map((x) => x.toString()).toList();
  }

  @override
  void dispose() { _txt.dispose(); super.dispose(); }

  Future<void> _pick() async {
    final picker = ImagePicker();
    final xs = await picker.pickMultiImage(imageQuality: 80, maxWidth: 2048);
    if (xs.isNotEmpty) setState(() => _newPhotos.addAll(xs));
  }

  Future<String?> _upload(XFile x, String uid) async {
    try {
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final path = 'poi-reviews/$uid/${DateTime.now().millisecondsSinceEpoch}_${_newPhotos.indexOf(x)}.$ext';
      await MotoGoSupabase.client.storage.from('media').uploadBinary(path, bytes);
      return MotoGoSupabase.client.storage.from('media').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final uid = MotoGoSupabase.currentUser?.id;
    if (uid == null) return;
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeReviewRatingReq'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final uploaded = <String>[..._photos];
      for (final x in _newPhotos) {
        final url = await _upload(x, uid);
        if (url != null) uploaded.add(url);
      }
      await MotoGoSupabase.client.rpc('submit_poi_review', params: {
        ...widget.target,
        'p_rating': _rating,
        'p_review_text': _txt.text.trim().isEmpty ? null : _txt.text.trim(),
        'p_photos': uploaded,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeReviewThanks'))));
      widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeReviewErr'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _photos.length + _newPhotos.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(widget.existing != null ? t(context).tr('routeReviewEdit') : t(context).tr('routeReviewAdd'),
              style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900, color: MotoGoColors.black)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => setState(() => _rating = i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(_rating >= i ? Icons.star : Icons.star_border, size: 38, color: const Color(0xFFF5B301)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _txt,
            maxLines: 4,
            decoration: InputDecoration(hintText: t(context).tr('routeReviewTextHint'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pick,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                border: Border.all(color: MotoGoColors.green, width: 1.2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo, size: 20, color: MotoGoColors.greenDarker),
                  const SizedBox(width: 8),
                  Text('${t(context).tr('routeReviewPhotos')}${total > 0 ? ' ($total)' : ''}',
                      style: const TextStyle(fontWeight: MotoGoTypo.w800, color: MotoGoColors.greenDarker)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
              ),
              child: Text(_busy ? '…' : t(context).tr('routeReviewSend'),
                  style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
