import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/supabase_client.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/friendly_error.dart';
import '../../../core/widgets/state_views.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../../auth/auth_provider.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../reservations/reservation_provider.dart';
import '../../../core/widgets/mg_nav_controls.dart';

/// Bottom sheet for managing notification and privacy consents.
class ConsentSheet extends ConsumerStatefulWidget {
  final String section;

  const ConsentSheet({required this.section, super.key});

  @override
  ConsumerState<ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends ConsumerState<ConsentSheet> {
  Map<String, bool> _consents = {};
  bool _loading = true;
  // Aktivní rezervace → souhlasy jsou po dobu pronájmu povinné (nelze odebrat).
  bool _locked = false;

  // value = i18n key, resolved via t(context).tr at render time.
  static const _notifKeys = {
    'consent_push': 'consentPush',
    'consent_email': 'consentEmail',
    'consent_sms': 'consentSms',
    'consent_whatsapp': 'consentWhatsapp',
    'marketing_consent': 'consentMarketing',
  };
  static const _privKeys = {
    'consent_vop': 'consentVop',
    'consent_gdpr': 'consentGdpr',
    'consent_data_processing': 'consentDataProcessing',
    'consent_contract': 'consentContract',
    'consent_photo': 'consentPhoto',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Object? _loadError;
  bool _saving = false;
  String? _saveError;

  /// Načtení s chybovým stavem — dřív offline / bez profilu točilo navždy.
  Future<void> _load() async {
    if (mounted && (_loadError != null || !_loading)) {
      setState(() {
        _loadError = null;
        _loading = true;
      });
    }
    try {
      await _loadInner();
    } catch (e) {
      FriendlyError.log('consent_load', e);
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadInner() async {
    final profile = await ref.read(profileProvider.future)
        .timeout(const Duration(seconds: 25));
    if (profile == null) {
      throw const AuthException('not_authenticated', statusCode: '401');
    }
    final keys = widget.section == 'notif' ? _notifKeys : _privKeys;
    final locked = ref.read(hasActiveReservationProvider);
    // Při aktivní rezervaci jsou souhlasy povinné — vynutíme zapnuto a pokud
    // byl některý v DB vypnutý, tiše ho zapneme, aby to reflektoval i Velín.
    final consents = {
      for (final k in keys.keys) k: locked ? true : profile[k] != false,
    };
    if (locked) {
      final toEnable = {
        for (final k in keys.keys)
          if (profile[k] == false) k: true,
      };
      if (toEnable.isNotEmpty) {
        final user = MotoGoSupabase.currentUser;
        if (user != null) {
          try {
            await MotoGoSupabase.client.from('profiles').update(toEnable).eq('id', user.id);
            ref.invalidate(profileProvider);
          } catch (_) {/* sken/oprava se může zopakovat při uložení */}
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _locked = locked;
      _consents = consents;
      _loading = false;
    });
  }

  /// Uložení: chyba → důvod, sheet zůstane otevřený se zvolenými souhlasy
  /// (dřív výjimka spadla potichu a nic se nestalo).
  Future<void> _save() async {
    if (_saving) return;
    final user = MotoGoSupabase.currentUser;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (user == null) {
        throw const AuthException('not_authenticated', statusCode: '401');
      }
      await MotoGoSupabase.client
          .from('profiles')
          .update(_consents)
          .eq('id', user.id);
    } catch (e) {
      // Chyba přímo v sheetu (toast by byl pod ním schovaný); volby zůstávají.
      FriendlyError.log('consent_save', e);
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = FriendlyError.of(e).compose(t(context), t(context).tr('eoSettingsSaveFail'));
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _saving = false);
      showMotoGoToast(context, icon: '✓', title: t(context).tr('saved'), message: t(context).tr('settingsSaved'));
      ref.invalidate(profileProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.section == 'notif' ? _notifKeys : _privKeys;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MgSheetTitleRow(title: Text(
            widget.section == 'notif' ? t(context).tr('notificationsSection') : t(context).tr('privacySection'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: MotoGoColors.black,
            ),
          )),
          const SizedBox(height: 16),
          if (_locked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MotoGoColors.g200),
              ),
              child: Row(children: [
                const Text('🔒', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t(context).tr('consentsLockedHint'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.black),
                  ),
                ),
              ]),
            ),
          ],
          if (_loading)
            const CircularProgressIndicator(color: MotoGoColors.green)
          else if (_loadError != null)
            MgErrorView(
              compact: true,
              error: _loadError,
              what: t(context).tr('eoSettingsLoadFail'),
              onRetry: _load,
              onBack: () => Navigator.pop(context),
              backLabel: t(context).tr('eoClose'),
            )
          else
            ...keys.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: GestureDetector(
                    onTap: () {
                      if (_locked) {
                        showMotoGoToast(context, icon: '🔒', title: t(context).tr('notifications'), message: t(context).tr('consentsLockedActive'));
                        return;
                      }
                      setState(() => _consents[e.key] = !(_consents[e.key] ?? false));
                    },
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          t(context).tr(e.value),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: (_consents[e.key] ?? false)
                              ? MotoGoColors.green
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (_consents[e.key] ?? false)
                                ? MotoGoColors.green
                                : MotoGoColors.g300,
                            width: 2,
                          ),
                        ),
                        child: (_consents[e.key] ?? false)
                            ? const Icon(Icons.check, size: 16, color: Colors.black)
                            : null,
                      ),
                    ]),
                  ),
                )),
          const SizedBox(height: 12),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_saveError!,
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.red, height: 1.35)),
            ),
          if (_loadError == null)
            ElevatedButton.icon(
              onPressed: _loading || _saving ? null : _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save, size: 16),
              label: Text(t(context).tr('save')),
            ),
        ]),
      ),
    );
  }
}
