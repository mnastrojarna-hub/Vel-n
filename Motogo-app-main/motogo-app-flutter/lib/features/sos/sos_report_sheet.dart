import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/friendly_error.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/error_feedback.dart';

/// Popis + fotky SOS hlášení. [cameraProblem] = fotku nešlo pořídit
/// (bez oprávnění / chyba kamery) → hlášení odešlo bez fotek.
typedef SosReportInput = ({String description, List<XFile> photos, bool cameraProblem});

/// Povinný sběr popisu + fotodokumentace před nahlášením incidentu.
/// Vrací `null` při zrušení; jinak popis (neprázdný) + fotky.
///
/// 2026-10-16: když fotoaparát nejde (oprávnění, porucha kamery), hlášení jde
/// odeslat i bez fotky — dřív to byla v nouzi slepá ulička. Sheet nejde
/// zavřít omylem tažením / klepnutím vedle; zrušení s vyplněným textem nebo
/// fotkami se potvrzuje.
Future<SosReportInput?> collectSosReport(BuildContext context, String typeLabel) {
  return showModalBottomSheet<SosReportInput>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SosReportSheet(typeLabel: typeLabel),
  );
}

class _SosReportSheet extends StatefulWidget {
  final String typeLabel;
  const _SosReportSheet({required this.typeLabel});

  @override
  State<_SosReportSheet> createState() => _SosReportSheetState();
}

class _SosReportSheetState extends State<_SosReportSheet> {
  final _descCtrl = TextEditingController();
  final _photos = <XFile>[];
  FriendlyError? _cameraProblem;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _dirty => _descCtrl.text.trim().isNotEmpty || _photos.isNotEmpty;

  Future<void> _cancel() async {
    if (_dirty && !await confirmDiscard(context)) return;
    if (mounted) Navigator.pop(context, null);
  }

  /// Vyfotí jednu fotku (kamera; při selhání nabídne galerii). Když nejde
  /// ani jedno, řekne proč a povolí odeslat bez fotky.
  Future<void> _capture() async {
    final picker = ImagePicker();
    Object? camError;
    try {
      final shot = await picker.pickImage(
          source: ImageSource.camera, imageQuality: 80, maxWidth: 2048);
      if (shot != null) setState(() => _photos.add(shot));
      return;
    } catch (e) {
      camError = e;
    }
    try {
      final shot = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 2048);
      if (shot != null) {
        setState(() => _photos.add(shot));
        return;
      }
    } catch (_) {}
    FriendlyError.log('sos_photo_capture', camError);
    if (!mounted) return;
    final fe = FriendlyError.of(camError, perm: DevicePerm.camera);
    setState(() => _cameraProblem = fe);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final noPhotoAllowed = _cameraProblem != null;
    final canSubmit = _descCtrl.text.trim().length >= 3 &&
        (_photos.isNotEmpty || noPhotoAllowed);
    final noPhotoReason = _cameraProblem == null
        ? ''
        : (_cameraProblem!.kind == FriendlyKind.permission
            ? tr.tr('eoPermReasonCamera')
            : tr.tr('eoSosCameraBroken'));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text('🆘 ${widget.typeLabel}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                ),
                IconButton(
                  tooltip: tr.tr('eoClose'),
                  onPressed: _cancel,
                  icon: const Icon(Icons.close, color: MotoGoColors.g500),
                ),
              ]),
              Text(tr.tr('sosReportRequiredHint'),
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
              const SizedBox(height: 16),
              Text('${tr.tr('sosDescriptionLabel')} *',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr.tr('sosDescriptionHint'),
                  hintStyle: const TextStyle(fontSize: 12, color: MotoGoColors.g400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: MotoGoColors.g200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: MotoGoColors.g200)),
                ),
              ),
              const SizedBox(height: 16),
              Text('${tr.tr('photoDocumentation')} ${noPhotoAllowed ? '' : '*'}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
              const SizedBox(height: 6),
              if (_photos.isNotEmpty) ...[
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_photos[i].path),
                          width: 64, height: 64, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _capture,
                style: OutlinedButton.styleFrom(
                  foregroundColor: MotoGoColors.greenDarker,
                  side: const BorderSide(color: MotoGoColors.greenDark),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: Text(
                    _photos.isEmpty ? tr.tr('takePhoto') : tr.tr('addAnotherPhoto'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              if (_cameraProblem != null && _photos.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MotoGoColors.amberBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MotoGoColors.amberBorder),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.trArgs('eoSosNoCameraBody', {'reason': noPhotoReason}),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                    if (_cameraProblem!.needsSettings)
                      TextButton(
                        onPressed: () => openFixSettings(_cameraProblem!),
                        child: Text(tr.tr('eoOpenSettings')),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(context, (
                          description: _descCtrl.text.trim(),
                          photos: List<XFile>.of(_photos),
                          cameraProblem: _photos.isEmpty && noPhotoAllowed,
                        ))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: MotoGoColors.g200,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: Text(
                    _photos.isEmpty && noPhotoAllowed
                        ? tr.tr('eoSosSendNoPhoto')
                        : tr.tr('yesReport'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cancel,
                style: TextButton.styleFrom(foregroundColor: MotoGoColors.g400),
                child: Text(tr.cancel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
