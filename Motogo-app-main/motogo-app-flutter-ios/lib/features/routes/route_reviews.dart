import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/debug_logger.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/net_image.dart';
import 'routes_provider.dart' show routesDataProvider;

double? _toD(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int _toI(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);

/// Řádek hvězdiček (plná/půl/prázdná) pro hodnotu 0–5.
Widget routeStars(double v, {double size = 18}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(v >= i ? Icons.star : (v >= i - 0.5 ? Icons.star_half : Icons.star_border), size: size, color: const Color(0xFFF5B301)),
      ],
    );

/// Karta jedné recenze (hvězdy, autor, text, fotky) — sdílí detail trasy i sheet z náhledu.
Widget routeReviewTile(BuildContext context, Map<String, dynamic> r) {
  final photos = (r['photos'] as List? ?? const []).map((e) => e.toString()).toList();
  final txt = r['review_text']?.toString() ?? '';
  final hidden = r['status'] == 'hidden';
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: hidden ? const Color(0xFFFBEAEA) : Colors.white,
      borderRadius: BorderRadius.circular(MotoGoRadius.card),
      border: Border.all(color: MotoGoColors.g200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            routeStars(_toI(r['rating']).toDouble(), size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (r['is_mine'] == true) ? t(context).tr('routeReviewYours') : (r['author']?.toString() ?? t(context).tr('routeReviewAnonymous')),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black, decoration: TextDecoration.none),
              ),
            ),
          ],
        ),
        if (txt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(txt, style: const TextStyle(fontSize: MotoGoTypo.sizeMd, height: 1.4, color: MotoGoColors.g600, decoration: TextDecoration.none)),
          ),
        if (photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: MgImage(photos[i], thumbWidth: 200, width: 72, height: 72, fit: BoxFit.cover,
                      placeholder: Container(width: 72, height: 72, color: MotoGoColors.greenPale),
                      error: Container(width: 72, height: 72, color: MotoGoColors.greenPale)),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Bottom sheet s recenzemi trasy — otevírá se hvězdičkami na kartě trasy
/// v seznamu. Načítá přes RPC `get_route_reviews` a umí recenzi rovnou NAPSAT
/// (stejný editor jako v detailu trasy) — hodnocení je tak na dva kliky přímo
/// ze seznamu tras.
void showRouteReviewsSheet(BuildContext context, {required String routeId, required String routeName}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReviewsSheet(routeId: routeId, routeName: routeName),
  );
}

class _ReviewsSheet extends ConsumerStatefulWidget {
  final String routeId;
  final String routeName;
  const _ReviewsSheet({required this.routeId, required this.routeName});

  @override
  ConsumerState<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends ConsumerState<_ReviewsSheet> {
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
      final res = await MotoGoSupabase.client.rpc('get_route_reviews', params: {'p_route_id': widget.routeId});
      if (!mounted) return;
      setState(() {
        if (res is Map) {
          _avg = _toD(res['avg']);
          _count = _toI(res['count']);
          _my = res['my'] is Map ? Map<String, dynamic>.from(res['my']) : null;
          _reviews = (res['reviews'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        _loading = false;
      });
    } catch (e) {
      AppDebugLogger.instance.log(LogCategory.api, 'get_route_reviews_failed',
          detail: e.toString(), data: {'route': widget.routeId});
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
      builder: (_) => _ReviewEditor(
        routeId: widget.routeId,
        existing: _my,
        onSaved: () {
          Navigator.of(context).maybePop(); // zavři editor
          _load();
          // Promítni nové hodnocení do seznamu tras (review_avg/count na kartách).
          ref.invalidate(routesDataProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(widget.routeName, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900, color: MotoGoColors.black, decoration: TextDecoration.none)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(t(context).tr('routeReviewsHeader'),
                  style: const TextStyle(fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800, color: MotoGoColors.g600, decoration: TextDecoration.none)),
              const Spacer(),
              if (_count > 0) ...[
                routeStars(_avg ?? 0, size: 16),
                const SizedBox(width: 6),
                Text('${(_avg ?? 0).toStringAsFixed(1)} · $_count ${t(context).tr('routeReviewCountSuffix')}',
                    style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w700, color: MotoGoColors.g600, decoration: TextDecoration.none)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Napsat / upravit recenzi přímo odsud (stejný editor jako v detailu).
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
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.greenDark))))
          else if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t(context).tr('routeReviewsNone'),
                  style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w600, color: MotoGoColors.g500, decoration: TextDecoration.none)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final r in _reviews) routeReviewTile(context, r)],
              ),
            ),
        ],
      ),
    );
  }
}

/// Recenze trasy — hvězdičkové hodnocení + textová recenze + fotky. Každý
/// přihlášený uživatel může jednu trasu ohodnotit (lze upravit). Čtení přes RPC
/// `get_route_reviews`, zápis přes `submit_route_review`, foto do bucketu `media`
/// pod prefixem `route-reviews/`.
class RouteReviewsSection extends ConsumerStatefulWidget {
  final String routeId;
  const RouteReviewsSection({super.key, required this.routeId});

  @override
  ConsumerState<RouteReviewsSection> createState() => _RouteReviewsSectionState();
}

class _RouteReviewsSectionState extends ConsumerState<RouteReviewsSection> {
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
      final res = await MotoGoSupabase.client.rpc('get_route_reviews', params: {'p_route_id': widget.routeId});
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
      builder: (_) => _ReviewEditor(
        routeId: widget.routeId,
        existing: _my,
        onSaved: () {
          Navigator.of(context).maybePop();
          _load();
          // Promítni nové hodnocení do seznamu tras (review_avg/count na kartách).
          ref.invalidate(routesDataProvider);
        },
      ),
    );
  }

  Future<void> _delete() async {
    try {
      await MotoGoSupabase.client.rpc('delete_route_review', params: {'p_route_id': widget.routeId});
      await _load();
      ref.invalidate(routesDataProvider);
    } catch (e) {
      AppDebugLogger.instance.log(LogCategory.error, 'delete_route_review_failed',
          detail: e.toString(), data: {'route': widget.routeId});
    }
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

/// Editor recenze (bottom sheet) — hvězdy, text, fotky.
class _ReviewEditor extends StatefulWidget {
  final String routeId;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _ReviewEditor({required this.routeId, required this.existing, required this.onSaved});

  @override
  State<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends State<_ReviewEditor> {
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
      final path = 'route-reviews/$uid/${DateTime.now().millisecondsSinceEpoch}_${_newPhotos.indexOf(x)}.$ext';
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
      await MotoGoSupabase.client.rpc('submit_route_review', params: {
        'p_route_id': widget.routeId,
        'p_rating': _rating,
        'p_review_text': _txt.text.trim().isEmpty ? null : _txt.text.trim(),
        'p_photos': uploaded,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeReviewThanks'))));
      widget.onSaved();
    } catch (e) {
      AppDebugLogger.instance.log(LogCategory.error, 'submit_route_review_failed',
          detail: e.toString(), data: {'route': widget.routeId, 'rating': _rating});
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
