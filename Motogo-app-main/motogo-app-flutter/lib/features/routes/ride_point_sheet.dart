import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/friendly_error.dart';
import '../../core/widgets/error_feedback.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'route_image.dart';
import '../../core/v2/flag/v2_scope.dart';
import 'v2/rides/ride_point_sheet_v2.dart';

/// Editor zastávky (bodu zájmu) na jízdě — název, popisek a fotky.
/// Zastávku lze i smazat. Vrací true, když se něco uložilo / smazalo.
Future<bool> showRidePointSheet(
  BuildContext context, {
  required String rideId,
  RidePoint? point,
  double? lat,
  double? lng,
}) async {
  // Něco se uložilo i když sheet zavřel uživatel (částečné uložení fotek).
  final changed = ValueNotifier(false);
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Tažení dolů by rozepsaný text a fotky zahodilo bez dotazu → zavírá
    // se ✕ / zpět (s potvrzením, když je co ztratit).
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _RidePointEditor(
        rideId: rideId,
        point: point,
        lat: lat ?? point?.lat,
        lng: lng ?? point?.lng,
        changed: changed,
      ),
    ),
  );
  final out = res == true || changed.value;
  changed.dispose();
  return out;
}

class _RidePointEditor extends StatefulWidget {
  final String rideId;
  final RidePoint? point;
  final double? lat;
  final double? lng;

  final ValueNotifier<bool> changed;

  const _RidePointEditor({
    required this.rideId,
    this.point,
    this.lat,
    this.lng,
    required this.changed,
  });

  @override
  State<_RidePointEditor> createState() => _RidePointEditorState();
}

class _RidePointEditorState extends State<_RidePointEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.point?.name ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.point?.note ?? '');
  late final List<String> _photos =
      [...(widget.point?.photos ?? const <String>[])];
  final List<XFile> _newPhotos = [];
  bool _busy = false;

  static const int _maxPhotos = 8;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Chyba k zobrazení přímo v sheetu (text a fotky zůstávají).
  String? _error;

  /// Id nově založené zastávky — opakované uložení ji upraví, nezaloží druhou.
  String? _savedId;

  bool get _dirty =>
      _newPhotos.isNotEmpty ||
      _name.text.trim() != (widget.point?.name ?? '') ||
      _note.text.trim() != (widget.point?.note ?? '');

  Future<void> _close() async {
    if (_busy) return;
    if (_dirty && !await confirmDiscard(context)) return;
    if (mounted) Navigator.of(context).pop(_savedId != null);
  }

  Future<void> _pick() async {
    final free = _maxPhotos - _photos.length - _newPhotos.length;
    if (free <= 0) return;
    final picker = ImagePicker();
    try {
      final xs = await picker.pickMultiImage(imageQuality: 78, maxWidth: 1600);
      if (xs.isEmpty) return;
      setState(() {
        _newPhotos.addAll(xs.take(free));
        _error = null;
      });
    } catch (e) {
      // Bez přístupu k fotkám — proč a jak (dřív výjimka potichu).
      FriendlyError.log('ride_point_pick', e);
      if (mounted) {
        setState(() => _error =
            FriendlyError.of(e, perm: DevicePerm.photos).compose(t(context), t(context).tr('eoPhotoPickFail')));
      }
    }
  }

  /// Uložení: neúspěch → sheet zůstane otevřený s důvodem (dřív se zavřel bez
  /// hlášky a text i fotky se ztratily); nenahrané fotky se řeknou nahlas.
  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = MotoGoSupabase.currentUser?.id;
    var failedPhotos = 0;
    if (_newPhotos.isNotEmpty && uid != null) {
      final batch = List<XFile>.of(_newPhotos);
      final urls = await uploadRidePhotos(uid, batch);
      failedPhotos = batch.length - urls.length;
      _photos.addAll(urls);
      // Nahrané pryč; nenahrané zůstanou k dalšímu pokusu.
      if (failedPhotos == 0) _newPhotos.clear();
    }
    final id = await saveRidePoint(
      rideId: widget.rideId,
      id: _savedId ?? widget.point?.id,
      kind: widget.point?.kind ?? 'stop',
      name: _name.text.trim(),
      note: _note.text.trim(),
      lat: widget.lat,
      lng: widget.lng,
      photos: _photos,
    );
    if (!mounted) return;
    final tr = t(context);
    if (id == null) {
      setState(() {
        _busy = false;
        _error = '${tr.tr('eoRidePointSaveFail')} ${tr.tr('eoTextKept')}';
      });
      return;
    }
    _savedId = id;
    widget.changed.value = true;
    if (failedPhotos > 0) {
      setState(() {
        _busy = false;
        _error = tr.trArgs('eoPhotosNotUploaded', {'n': failedPhotos});
      });
      return;
    }
    setState(() => _busy = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final p = widget.point;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    final ok = await deleteRidePoint(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = t(context).tr('eoRidePointDeleteFail'));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    // v2: stejný stav, ovladače i akce — jen nový vzhled (PLAN §2.7).
    if (MgV2.on(context)) {
      return RidePointSheetV2View(
        isNew: widget.point == null,
        busy: _busy,
        error: _error,
        name: _name,
        note: _note,
        photos: _photos,
        newPhotoPaths: [for (final x in _newPhotos) x.path],
        maxPhotos: _maxPhotos,
        onDelete: widget.point != null ? _delete : null,
        onClose: _close,
        onSave: _save,
        onPick: _pick,
        onRemovePhoto: (i) => setState(() => _photos.removeAt(i)),
        onRemoveNew: (i) => setState(() => _newPhotos.removeAt(i)),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t(context).tr(widget.point == null
                        ? 'ridePointNew'
                        : 'ridePointEdit'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH3,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  ),
                ),
                if (widget.point != null)
                  GestureDetector(
                    onTap: _delete,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 22, color: Color(0xFFD93636)),
                    ),
                  ),
                // Viditelné zavření (tažení dolů je vypnuté kvůli ztrátě dat).
                IconButton(
                  tooltip: t(context).tr('eoClose'),
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: MotoGoColors.g500),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD93636), height: 1.35)),
            ],
            const SizedBox(height: 12),
            _label(context, 'ridePointName'),
            _field(_name, t(context).tr('ridePointNameHint'), maxLines: 1),
            const SizedBox(height: 12),
            _label(context, 'ridePointNote'),
            _field(_note, t(context).tr('ridePointNoteHint'), maxLines: 4),
            const SizedBox(height: 14),
            _label(context, 'ridePointPhotos'),
            const SizedBox(height: 8),
            _photoRow(),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: MotoGoColors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: MotoGoColors.black))
                    : Text(
                        t(context).tr('ridePointSave'),
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeXl,
                            fontWeight: MotoGoTypo.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String key) => Text(
        t(context).tr(key),
        style: const TextStyle(
            fontSize: MotoGoTypo.sizeMd,
            fontWeight: MotoGoTypo.w800,
            color: MotoGoColors.g600,
            decoration: TextDecoration.none),
      );

  Widget _field(TextEditingController c, String hint, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          style: const TextStyle(
              fontSize: MotoGoTypo.sizeBase,
              fontWeight: MotoGoTypo.w600,
              color: MotoGoColors.black),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: MotoGoColors.g100,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MotoGoRadius.xl),
              borderSide: const BorderSide(color: MotoGoColors.g200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MotoGoRadius.xl),
              borderSide: const BorderSide(color: MotoGoColors.g200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MotoGoRadius.xl),
              borderSide: const BorderSide(color: MotoGoColors.green, width: 1.6),
            ),
          ),
        ),
      );

  Widget _photoRow() {
    final tiles = <Widget>[
      for (var i = 0; i < _photos.length; i++)
        _tile(
          child: RouteImage(
            url: _photos[i],
            targetWidth: 260,
            placeholder: (_) => _imgFallback(),
            error: (_) => _imgFallback(),
          ),
          onRemove: () => setState(() => _photos.removeAt(i)),
        ),
      for (var i = 0; i < _newPhotos.length; i++)
        _tile(
          child: Image.file(File(_newPhotos[i].path), fit: BoxFit.cover),
          onRemove: () => setState(() => _newPhotos.removeAt(i)),
        ),
      if (_photos.length + _newPhotos.length < _maxPhotos)
        GestureDetector(
          onTap: _pick,
          child: Container(
            width: 86,
            height: 86,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MotoGoColors.green, width: 1.2),
            ),
            child: const Icon(Icons.add_a_photo,
                size: 22, color: MotoGoColors.greenDarker),
          ),
        ),
    ];
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: tiles,
      ),
    );
  }

  Widget _tile({required Widget child, required VoidCallback onRemove}) =>
      Padding(
        padding: const EdgeInsets.only(right: 10, top: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 86, height: 86, child: child),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: MotoGoColors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _imgFallback() => Container(
        color: MotoGoColors.g200,
        child: const Icon(Icons.image, size: 20, color: MotoGoColors.g400),
      );
}
