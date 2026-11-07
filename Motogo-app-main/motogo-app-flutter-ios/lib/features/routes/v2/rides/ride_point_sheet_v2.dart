import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../route_image.dart';

/// v2 body of the stop editor (light sheet): title, delete (existing
/// stop), ✕ (the old close with the discard confirm), the error in place
/// (text and photos stay), name, note, photos (≤ 8) and UložIT. Everything
/// — controllers, photo lists, busy, error, callbacks — is the old
/// `_RidePointEditorState`'s.
class RidePointSheetV2View extends StatelessWidget {
  final bool isNew;
  final bool busy;
  final String? error;
  final TextEditingController name;
  final TextEditingController note;
  final List<String> photos;
  final List<String> newPhotoPaths;
  final int maxPhotos;
  final VoidCallback? onDelete;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onPick;
  final ValueChanged<int> onRemovePhoto;
  final ValueChanged<int> onRemoveNew;

  const RidePointSheetV2View({
    super.key,
    required this.isNew,
    required this.busy,
    required this.error,
    required this.name,
    required this.note,
    required this.photos,
    required this.newPhotoPaths,
    required this.maxPhotos,
    required this.onDelete,
    required this.onClose,
    required this.onSave,
    required this.onPick,
    required this.onRemovePhoto,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final count = photos.length + newPhotoPaths.length;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(tr.tr(isNew ? 'ridePointNew' : 'ridePointEdit'), style: MgType.h3.copyWith(color: MgColors.ink)),
              ),
            ),
            if (onDelete != null)
              Semantics(
                button: true,
                label: tr.tr('v2RidePointDelete'),
                excludeSemantics: true,
                child: MgPress(
                  scale: 0.9,
                  onTap: busy ? null : onDelete,
                  child: const SizedBox(width: 44, height: 44, child: Center(child: MgIcon(MgIcons.trash, size: 20, color: MgColors.err))),
                ),
              ),
            const SizedBox(width: 4),
            MgV2Back(onTap: onClose, close: true, style: MgBackStyle.light, label: tr.tr('eoClose')),
          ]),
          if (error != null) ...[
            const SizedBox(height: 10),
            MgStateBanner(tone: MgTone.err, title: error!),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: name,
            maxLines: 1,
            decoration: mgInputDecoration(context, label: tr.tr('ridePointName'), hint: tr.tr('ridePointNameHint')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 4,
            decoration: mgInputDecoration(context, label: tr.tr('ridePointNote'), hint: tr.tr('ridePointNoteHint')),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(tr.tr('ridePointPhotos'), style: MgType.title.copyWith(color: MgColors.ink))),
            Text(tr.trArgs('v2RidePhotosCount', {'n': count, 'max': maxPhotos}),
                style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta))),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
              for (var i = 0; i < photos.length; i++)
                _Thumb(
                  onRemove: () => onRemovePhoto(i),
                  child: RouteImage(url: photos[i], targetWidth: 260, placeholder: _fallback, error: _fallback),
                ),
              for (var i = 0; i < newPhotoPaths.length; i++)
                _Thumb(onRemove: () => onRemoveNew(i), child: Image.file(File(newPhotoPaths[i]), fit: BoxFit.cover)),
              if (count < maxPhotos)
                Semantics(
                  button: true,
                  label: tr.tr('v2RideAddPhoto'),
                  excludeSemantics: true,
                  child: MgPress(
                    onTap: onPick,
                    child: Container(
                      width: 86,
                      height: 86,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: MgColors.well,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MgColors.lineInput, width: 1.5),
                      ),
                      child: const Center(child: MgIcon(MgIcons.cameraAlt, size: 24, color: MgColors.link)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          MgBtnInk(label: tr.tr('ridePointSave'), neonLabel: true, busy: busy, onTap: busy ? null : onSave),
        ]),
      ),
    );
  }

  static Widget _fallback(BuildContext _) => const ColoredBox(
        color: MgColors.well,
        child: Center(child: MgIcon(MgIcons.image, size: 20, color: MgColors.meta)),
      );
}

class _Thumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const _Thumb({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12, top: 6),
        child: Stack(clipBehavior: Clip.none, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 86, height: 86, child: child)),
          Positioned(
            right: -10,
            top: -10,
            child: Semantics(
              button: true,
              label: t(context).tr('v2RideRemovePhoto'),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: MgColors.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: MgColors.surface, width: 1.5),
                      ),
                      child: const Center(child: MgIcon(MgIcons.close, size: 14, color: MgColors.onDark)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
}
