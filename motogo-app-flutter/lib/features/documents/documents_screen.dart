import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Moje doklady — matches Capacitor original s-docs screen.
/// Shows: info banners, scan button (camera), upload button (gallery),
/// and list of scanned docs only (no invoices/contracts).
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verifiedAsync = ref.watch(docsVerifiedProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.png', width: 24, height: 24, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 24, height: 24, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 14, color: Colors.white)))),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(context).tr('myDocuments'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(t(context).tr('docsBeforeFirst'), style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
        ]),
        backgroundColor: MotoGoColors.dark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info banner — only when docs are NOT verified
            verifiedAsync.when(
              data: (v) {
                if (v.isComplete) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MotoGoColors.amberBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MotoGoColors.amberBorder),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('⚠️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      t(context).tr('docsRequiredInfo'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E), height: 1.4),
                    )),
                  ]),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),

            // Verification status
            verifiedAsync.when(
              data: (v) => _VerificationBanner(verification: v),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // NASKENOVAT DOKLADY KAMEROU button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.push(Routes.docScan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📷', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(t(context).tr('scanDocsCamera'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ]),
              ),
            ),
            const SizedBox(height: 10),

            // NAHRÁT Z GALERIE button
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => _uploadFromGallery(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MotoGoColors.greenDark,
                  side: const BorderSide(color: MotoGoColors.green, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📁', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(t(context).tr('uploadFromGallery'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // Doc verification status — based solely on profile verification
            verifiedAsync.when(
              data: (v) {
                if (!v.hasIdOrPassport && !v.hasLicense) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MotoGoColors.amberBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('⚠ ${t(context).tr('docsNotVerified')}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                      const SizedBox(height: 4),
                      Text(t(context).tr('docsNotVerifiedDesc'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4)),
                    ]),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context).tr('docsStatus'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    _DocStatus(
                      icon: '🪪',
                      label: t(context).tr('idCardPassport'),
                      verified: v.hasIdOrPassport,
                      onReset: () => _resetDoc(context, ref, 'id_card'),
                    ),
                    _DocStatus(
                      icon: '🏍️',
                      label: t(context).tr('driversLicense'),
                      verified: v.hasLicense,
                      onReset: () => _resetDoc(context, ref, 'drivers_license'),
                    ),
                    const SizedBox(height: 12),
                    if (v.isComplete)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: MotoGoColors.greenPale,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Text('✅', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            t(context).tr('docsVerifiedDesc'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                          )),
                        ]),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
              error: (_, __) => Text(t(context).tr('loadingError'), style: const TextStyle(color: MotoGoColors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetDoc(BuildContext context, WidgetRef ref, String docType) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).tr('deleteDocTitle'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(t(context).tr('deleteDocDesc'), style: const TextStyle(fontSize: 13)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t(context).cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(context).tr('deleteDoc'), style: const TextStyle(color: MotoGoColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    showMotoGoToast(context, icon: '⏳', title: t(context).tr('deleting'), message: t(context).tr('deletingDoc'));
    final ok = await resetDocVerification(docType);
    if (!context.mounted) return;
    ref.invalidate(docsVerifiedProvider);
    showMotoGoToast(context,
      icon: ok ? '✅' : '❌',
      title: ok ? t(context).tr('deleted') : t(context).error,
      message: ok ? t(context).tr('docRemoved') : t(context).tr('deleteFailed'),
    );
  }

  Future<void> _uploadFromGallery(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
    if (photo == null) return;
    if (!context.mounted) return;
    showMotoGoToast(context, icon: '⏳', title: t(context).tr('uploading'), message: t(context).tr('processingDoc'));
    await uploadDocPhoto(photo, ScanDocType.idCard);
    final result = await scanDocument(photo, ScanDocType.idCard);
    if (result != null) {
      await saveOcrToProfile(result);
    }
    if (!context.mounted) return;
    ref.invalidate(docsVerifiedProvider);
    showMotoGoToast(context, icon: '✅', title: t(context).tr('uploaded'), message: t(context).tr('docProcessed'));
  }
}

class _VerificationBanner extends StatelessWidget {
  final DocsVerification verification;
  const _VerificationBanner({required this.verification});

  @override
  Widget build(BuildContext context) {
    if (verification.isComplete) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MotoGoColors.greenPale,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Text('✅', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(context).tr('docsVerified'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
            Text(t(context).tr('idPassportShort'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g600)),
          ])),
        ]),
      );
    }

    final missing = <String>[];
    if (!verification.hasIdOrPassport) missing.add(t(context).tr('idOrPassport'));
    if (!verification.hasLicense) missing.add(t(context).tr('driversLicense').toLowerCase());

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MotoGoColors.amberBorder),
      ),
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(context).tr('docsNotVerified'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
          Text('${t(context).tr('missing')}: ${missing.join(", ")}', style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
        ])),
      ]),
    );
  }
}

class _DocStatus extends StatelessWidget {
  final String icon, label;
  final bool verified;
  final VoidCallback onReset;
  const _DocStatus({required this.icon, required this.label, required this.verified, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: verified ? MotoGoColors.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: verified ? MotoGoColors.green.withValues(alpha: 0.3) : MotoGoColors.g200),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          Text(
            verified ? t(context).tr('verified') : t(context).tr('notVerified'),
            style: TextStyle(fontSize: 11,
              color: verified ? MotoGoColors.greenDarker : MotoGoColors.g400,
              fontWeight: verified ? FontWeight.w600 : FontWeight.w500),
          ),
        ])),
        if (verified) ...[
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: MotoGoColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.delete_outline, size: 14, color: MotoGoColors.red),
                SizedBox(width: 2),
                Text(t(context).tr('deleteDoc'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle, color: MotoGoColors.greenDark, size: 22),
        ] else
          const Icon(Icons.radio_button_unchecked, color: MotoGoColors.g400, size: 22),
      ]),
    );
  }
}
