import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/offline_guard.dart';
import '../auth/widgets/toast_helper.dart';
import '../../core/friendly_error.dart';
import '../../core/widgets/error_feedback.dart';
import '../../core/widgets/state_views.dart';
import 'document_models.dart' show ScanDocType;
import 'document_provider.dart';
import 'docs_gate_provider.dart';
import 'docs_gate_widgets.dart';
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/v2/flag/v2_scope.dart';
import '../profile/v2/sheets/profile_dialogs_v2.dart' show DestructiveDialogV2;
import 'v2/docs_view_v2.dart';

/// Moje doklady — matches Capacitor original s-docs screen.
/// Shows: info banners, scan button (camera), upload button (gallery),
/// and list of scanned docs only (no invoices/contracts).
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kompletnost dokladů dle brány kódů (obě strany OP/pasu a ŘP), bez
    // odpovědi RPC dle profilových *_verified_at (docsScreenStatusProvider).
    // Obnova po nahrání = změna závislosti → `skipLoadingOnReload`, ať stav
    // neprobliká (jako dřív u přímo invalidovaného docsVerifiedProvider).
    final verifiedAsync = ref.watch(docsScreenStatusProvider);

    // Na /docs se chodí i přes context.go (děkovací stránka, FAB) —
    // pak není v zásobníku co popnout a šipka dřív nedělala nic.
    void onBack() {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.profile);
            }
          }

    // v2 vzhled (kill-switch app_v2_ui, PLAN §2.5.2): stejné akce a stav.
    if (MgV2.on(context)) {
      return DocsViewV2(
        verifiedAsync: verifiedAsync,
        onBack: onBack,
        onScan: () => context.push(Routes.docScan),
        onScanDl: () => context.push('${Routes.docScan}?mode=dl_only'),
        onUpload: () => _uploadFromGallery(context, ref),
        onReset: (docType) => _resetDoc(context, ref, docType),
        onRetry: () => ref.invalidate(docsScreenStatusProvider),
      );
    }

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: MgBackTap(
          onTap: onBack,
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.webp', width: 24, height: 24, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 24, height: 24, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 14, color: Colors.black)))),
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
              skipLoadingOnReload: true,
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
              skipLoadingOnReload: true,
              data: (v) => _VerificationBanner(verification: v),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),

            // Scan tips
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.g100,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t(context).tr('scanTips'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g600, height: 1.5))),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // NASKENOVAT DOKLADY KAMEROU button
            SizedBox(
              height: 52,
              child: PressableScale(
                child: ElevatedButton(
                onPressed: () => context.push(Routes.docScan),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📷', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(t(context).tr('scanDocsCamera'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ]),
              ),
              ),
            ),
            const SizedBox(height: 10),

            // NASKENOVAT POUZE ŘP button — shown when OP verified but ŘP missing
            verifiedAsync.when(
              skipLoadingOnReload: true,
              data: (v) {
                if (v.hasIdOrPassport && !v.hasLicense) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => context.push('${Routes.docScan}?mode=dl_only'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MotoGoColors.greenDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Text('🏍️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Text(t(context).tr('scanDlOnly'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                        ]),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

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

            // Doc verification status — brána kódů (obě strany), záloha profil
            verifiedAsync.when(
              skipLoadingOnReload: true,
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
                      if (v.gate != null && !v.gate!.ok) DocsGateMissingLine(gate: v.gate!),
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
                      onScan: v.hasIdOrPassport ? null : () => context.push(Routes.docScan),
                    ),
                    _DocStatus(
                      icon: '🏍️',
                      label: t(context).tr('driversLicense'),
                      verified: v.hasLicense,
                      onReset: () => _resetDoc(context, ref, 'drivers_license'),
                      onScan: v.hasLicense ? null : () => context.push('${Routes.docScan}?mode=dl_only'),
                    ),
                    // Co přesně chybí pro vydání kódů (strana dokladu, věk,
                    // platnost / skupina ŘP) — jeden řádek dle brány.
                    if (v.gate != null && !v.gate!.ok)
                      DocsGateMissingLine(gate: v.gate!),
                    const SizedBox(height: 12),
                    if (v.codesReady)
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
              error: (e, _) => MgErrorView(
                compact: true,
                error: e,
                what: t(context).tr('eoDocsStatusFail'),
                onRetry: () => ref.invalidate(docsScreenStatusProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetDoc(BuildContext context, WidgetRef ref, String docType) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => MgV2.on(ctx)
          // v2 vzhled (T6) — stejné texty a návratové hodnoty.
          ? DestructiveDialogV2(
              title: t(context).tr('deleteDocTitle'),
              body: t(context).tr('deleteDocDesc'),
              cancelLabel: t(context).cancel,
              deleteLabel: t(context).tr('deleteDoc'),
              onCancel: () => Navigator.pop(ctx, false),
              onDelete: () => Navigator.pop(ctx, true),
            )
          : AlertDialog(
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
    ref.invalidate(docsGateChecklistProvider);
    showMotoGoToast(context,
      icon: ok ? '✅' : '❌',
      title: ok ? t(context).tr('deleted') : t(context).error,
      message: ok ? t(context).tr('docRemoved') : t(context).tr('deleteFailed'),
    );
  }

  Future<void> _uploadFromGallery(BuildContext context, WidgetRef ref) async {
    final kind = await pickGalleryDocKind(context);
    if (kind == null || !context.mounted) return;
    final (docType, docSide, stepKey) = kind;
    final picker = ImagePicker();
    final XFile? photo;
    try {
      photo = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
    } catch (e) {
      // Bez přístupu k fotkám: proč + Otevřít nastavení (dřív výjimka potichu).
      if (context.mounted) {
        showErrorSnack(context, t(context).tr('eoGalleryOpenFail'), e,
            where: 'docs_gallery_pick', perm: DevicePerm.photos);
      }
      return;
    }
    if (photo == null) return;
    if (!context.mounted) return;
    await _processGalleryPhoto(context, ref, photo, docType, docSide, stepKey);
  }

  /// Zpracování vybrané fotky: bez sítě hned důvod (dřív minuty v modálu),
  /// průběh s „pokus n/3" a po 20 s „Zrušit", celkový limit. „Zkusit znovu"
  /// zpracuje STEJNOU fotku (bez nového výběru).
  Future<void> _processGalleryPhoto(BuildContext context, WidgetRef ref, XFile photo,
      ScanDocType docType, String? docSide, String stepKey) async {
    final tr = t(context);
    void retry() => _processGalleryPhoto(context, ref, photo, docType, docSide, stepKey);
    if (!await _deviceOnline()) {
      if (context.mounted) {
        showErrorSnack(context, tr.tr('eoDocUploadWhat'), const SocketException('offline'),
            where: 'docs_gallery_offline', onRetry: retry);
      }
      return;
    }
    if (!context.mounted) return;
    final progress = MgProgress.show(context, tr.tr('processingDoc'),
        cancelAfter: const Duration(seconds: 20));
    final op = _scanAndSave(photo, docType, docSide, stepKey, progress, tr);
    DocUploadResult upload;
    var abandoned = false;
    try {
      upload = await progress.guard(op).timeout(const Duration(seconds: 150));
    } on MgCancelled {
      abandoned = true;
      upload = const DocUploadResult(errorDetail: 'cancelled');
    } catch (e) {
      abandoned = e is TimeoutException;
      upload = DocUploadResult(errorDetail: '$e', cause: e);
    } finally {
      progress.close();
    }
    if (abandoned) {
      // Nahrání mohlo na pozadí doběhnout → pak obnov seznam dokladů.
      unawaited(op.then((_) {
        if (context.mounted) _refreshDocs(ref);
      }, onError: (_) {}));
    }
    if (!context.mounted) return;
    _refreshDocs(ref);
    final fe = FriendlyError.of(upload.cause);
    if (progress.cancelled) {
      showMotoGoToast(context, icon: 'ℹ️',
          title: tr.tr('r3UploadStoppedTitle'), message: tr.tr('r3UploadStoppedBody'));
    } else if (upload.ok) {
      // Fotka uložená → strana dokladu je nahraná (kódy dle brány dokladů).
      showMotoGoToast(context, icon: '✅', title: tr.tr('uploaded'), message: tr.tr('docProcessed'));
    } else if (upload.cause != null && (fe.isNetwork || fe.kind == FriendlyKind.server)) {
      // Síť / server: skutečný důvod (dřív mylně „naskenuj doklad kamerou").
      showErrorSnack(context, tr.tr('eoDocUploadWhat'), upload.cause,
          where: 'docs_gallery_upload', onRetry: retry);
    } else {
      // Upload nebo OCR selhaly — doveď uživatele na skener s kamerou,
      // kde má full retry + contact fallback flow.
      showMotoGoToast(context, icon: '⚠️',
          title: tr.tr('scanFailed'),
          message: tr.tr('scanUseCamera'));
    }
  }

  void _refreshDocs(WidgetRef ref) {
    ref.invalidate(docsVerifiedProvider);
    ref.invalidate(docsGateChecklistProvider);
  }

  /// Zapnutá Wi-Fi / data? Chyba pluginu = nevíme → zkusit (rozhodne server).
  static Future<bool> _deviceOnline() async {
    try {
      return await OfflineGuard.isOnline().timeout(const Duration(seconds: 3));
    } catch (_) {
      return true;
    }
  }

  /// OCR + uložení fotky. Výpadek spojení při OCR → rovnou důvod (fotka by
  /// se na stejném signálu neuložila); jinak se fotka uloží VŽDY, i když OCR
  /// selhalo (zákazník o ni nepřijde).
  static Future<DocUploadResult> _scanAndSave(XFile photo, ScanDocType docType,
      String? docSide, String stepKey, MgProgress progress, AppTranslations tr) async {
    final base = tr.tr('processingDoc');
    final scan = await scanDocumentWithRetry(photo, docType, retryOnNetwork: false,
        onAttempt: (n, max) {
      if (n > 1) progress.update('$base · ${tr.tr('attempt')} $n/$max');
    });
    if (scan.errorCode == 'network') {
      return DocUploadResult(
          errorDetail: scan.errorDetail ?? 'network', cause: const SocketException('offline'));
    }
    progress.update(tr.tr('r3SavingDocPhoto'));
    final upload = await uploadDocPhoto(photo, docType, mindeeOk: scan.ok, docSide: docSide);
    if (scan.data != null) {
      await saveOcrToProfile(scan.data!, docType: docType, stepKey: stepKey);
    }
    return upload;
  }
}

class _VerificationBanner extends StatelessWidget {
  final DocsScreenStatus verification;
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
  final VoidCallback? onScan;
  const _DocStatus({required this.icon, required this.label, required this.verified, required this.onReset, this.onScan});

  @override
  Widget build(BuildContext context) {
    final child = Container(
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.delete_outline, size: 14, color: MotoGoColors.red),
                const SizedBox(width: 2),
                Text(t(context).tr('deleteDoc'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle, color: MotoGoColors.greenDark, size: 22),
        ] else ...[
          if (onScan != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: MotoGoColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.camera_alt, size: 14, color: MotoGoColors.greenDark),
                const SizedBox(width: 2),
                Text(t(context).tr('scan'), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.greenDark)),
              ]),
            )
          else
            const Icon(Icons.radio_button_unchecked, color: MotoGoColors.g400, size: 22),
        ],
      ]),
    );

    if (onScan != null) {
      return GestureDetector(onTap: onScan, child: child);
    }
    return child;
  }
}
