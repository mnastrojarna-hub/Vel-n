import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';

/// Sdílené kousky pro komunitní návrhy (trasa / bod zájmu):
/// info banner o moderaci, výběr fotek s náhledy, upload a success sheet.

/// Zelený info banner — vysvětluje, co se s návrhem stane (moderace).
class SubmitIntroBanner extends StatelessWidget {
  const SubmitIntroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.greenPale,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        border: Border.all(color: MotoGoColors.green, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t(context).tr('submitModerationNote'),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w600,
                color: MotoGoColors.greenDarker,
                height: 1.4,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Výběr fotek z mobilu: mřížka náhledů (Image.file) s křížkem na smazání
/// + dlaždice „Přidat fotku". Fotky se komprimují už při výběru (1600 px / q78).
class SubmitPhotosSection extends StatelessWidget {
  final List<XFile> photos;
  final int max;
  final String hint;
  final ValueChanged<List<XFile>> onChanged;

  const SubmitPhotosSection({
    super.key,
    required this.photos,
    required this.onChanged,
    required this.hint,
    this.max = 6,
  });

  Future<void> _add(BuildContext context) async {
    final picker = ImagePicker();
    if (max == 1) {
      final x = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 78, maxWidth: 1600);
      if (x != null) onChanged([x]);
      return;
    }
    final xs = await picker.pickMultiImage(imageQuality: 78, maxWidth: 1600);
    if (xs.isEmpty) return;
    final next = [...photos, ...xs];
    onChanged(next.length > max ? next.sublist(0, max) : next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              t(context).tr('submitPhotos'),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeLg,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.black,
                decoration: TextDecoration.none,
              ),
            ),
            if (max > 1) ...[
              const SizedBox(width: 6),
              Text(
                '${photos.length}/$max',
                style: const TextStyle(
                  fontSize: MotoGoTypo.sizeMd,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g400,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: const TextStyle(
            fontSize: MotoGoTypo.sizeMd,
            fontWeight: MotoGoTypo.w600,
            color: MotoGoColors.g500,
            height: 1.35,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 86,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < photos.length; i++) _thumb(context, i),
              if (photos.length < max) _addTile(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumb(BuildContext context, int i) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(photos[i].path),
              width: 86,
              height: 86,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 86, height: 86, color: MotoGoColors.g200,
                child: const Icon(Icons.broken_image, color: MotoGoColors.g400),
              ),
            ),
          ),
          // První fotka = titulní (hvězdička)
          if (i == 0 && max > 1)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.star, size: 11, color: Colors.black),
              ),
            ),
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              onTap: () {
                final next = [...photos]..removeAt(i);
                onChanged(next);
              },
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
  }

  Widget _addTile(BuildContext context) {
    return GestureDetector(
      onTap: () => _add(context),
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MotoGoColors.green, width: 1.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo, size: 22, color: MotoGoColors.greenDarker),
            const SizedBox(height: 4),
            Text(
              t(context).tr('submitAddPhoto'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: MotoGoTypo.w800,
                color: MotoGoColors.greenDarker,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nahraje fotky návrhu do bucketu `media` (prefix `user-pois/` — jediný
/// povolený pro authenticated upload komunitního obsahu). Vrací veřejné URL;
/// fotky, které se nepovedlo nahrát, tiše přeskočí.
Future<List<String>> uploadSubmitPhotos(String uid, List<XFile> photos) async {
  final urls = <String>[];
  final ts = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < photos.length; i++) {
    try {
      final x = photos[i];
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final path = 'user-pois/$uid/${ts}_$i.$ext';
      await MotoGoSupabase.client.storage.from('media').uploadBinary(path, bytes);
      urls.add(MotoGoSupabase.client.storage.from('media').getPublicUrl(path));
    } catch (_) {/* přeskočit vadnou fotku, návrh nepadá */}
  }
  return urls;
}

/// Success sheet po odeslání návrhu — velká fajfka + vysvětlení moderace.
/// Zavře se tlačítkem; poté volající obvykle popne submit obrazovku.
Future<void> showSubmitSuccess(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isDismissible: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: MotoGoColors.greenPale,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, size: 40, color: MotoGoColors.greenDark),
            ),
            const SizedBox(height: 14),
            Text(
              t(c).tr('submitSuccessTitle'),
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeH2,
                fontWeight: MotoGoTypo.w900,
                color: MotoGoColors.black,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t(c).tr('submitSuccessBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w600,
                color: MotoGoColors.g600,
                height: 1.45,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(c).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: MotoGoColors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
                ),
                child: Text(
                  t(c).tr('submitSuccessOk'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
