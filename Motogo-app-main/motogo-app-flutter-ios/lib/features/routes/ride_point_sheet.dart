import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'route_image.dart';

/// Editor zastávky (bodu zájmu) na jízdě — název, popisek a fotky.
/// Zastávku lze i smazat. Vrací true, když se něco uložilo / smazalo.
Future<bool> showRidePointSheet(
  BuildContext context, {
  required String rideId,
  RidePoint? point,
  double? lat,
  double? lng,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
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
      ),
    ),
  );
  return res == true;
}

class _RidePointEditor extends StatefulWidget {
  final String rideId;
  final RidePoint? point;
  final double? lat;
  final double? lng;

  const _RidePointEditor({
    required this.rideId,
    this.point,
    this.lat,
    this.lng,
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

  Future<void> _pick() async {
    final free = _maxPhotos - _photos.length - _newPhotos.length;
    if (free <= 0) return;
    final picker = ImagePicker();
    final xs = await picker.pickMultiImage(imageQuality: 78, maxWidth: 1600);
    if (xs.isEmpty) return;
    setState(() => _newPhotos.addAll(xs.take(free)));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final uid = MotoGoSupabase.currentUser?.id;
    var photos = _photos;
    if (_newPhotos.isNotEmpty && uid != null) {
      final urls = await uploadRidePhotos(uid, _newPhotos);
      photos = [...photos, ...urls];
    }
    final id = await saveRidePoint(
      rideId: widget.rideId,
      id: widget.point?.id,
      kind: widget.point?.kind ?? 'stop',
      name: _name.text.trim(),
      note: _note.text.trim(),
      lat: widget.lat,
      lng: widget.lng,
      photos: photos,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(id != null);
  }

  Future<void> _delete() async {
    final p = widget.point;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    final ok = await deleteRidePoint(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
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
