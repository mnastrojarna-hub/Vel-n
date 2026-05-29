import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/supabase_client.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../auth/auth_provider.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../reservations/reservation_provider.dart';

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

  static const _notifKeys = {
    'consent_push': 'Push notifikace',
    'consent_email': 'Email komunikace',
    'consent_sms': 'SMS komunikace',
    'consent_whatsapp': 'WhatsApp komunikace',
    'marketing_consent': 'Marketingový souhlas',
  };
  static const _privKeys = {
    'consent_vop': 'VOP — všeobecné obchodní podmínky',
    'consent_gdpr': 'GDPR — zpracování osobních údajů',
    'consent_data_processing': 'Zpracování dat pro provoz služby',
    'consent_contract': 'Četl/a jsem návrh smlouvy na motogo24.cz a souhlasím',
    'consent_photo': 'Fotografování dokladů a motorky',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await ref.read(profileProvider.future);
    if (profile == null) return;
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

  Future<void> _save() async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    await MotoGoSupabase.client
        .from('profiles')
        .update(_consents)
        .eq('id', user.id);
    if (mounted) {
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
          Text(
            widget.section == 'notif' ? t(context).tr('notificationsSection') : t(context).tr('privacySection'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: MotoGoColors.black,
            ),
          ),
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
                          e.value,
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
          ElevatedButton.icon(
            onPressed: _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Uložit'),
          ),
        ]),
      ),
    );
  }
}
