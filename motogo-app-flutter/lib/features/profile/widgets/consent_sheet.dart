import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/supabase_client.dart';
import '../../auth/auth_provider.dart';
import '../../auth/widgets/toast_helper.dart';

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
    setState(() {
      _consents = {for (final k in keys.keys) k: profile[k] == true};
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
      showMotoGoToast(context, icon: '✓', title: 'Uloženo', message: 'Nastavení bylo uloženo');
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
            widget.section == 'notif' ? 'Notifikace' : 'Soukromí a souhlasy',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: MotoGoColors.black,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const CircularProgressIndicator(color: MotoGoColors.green)
          else
            ...keys.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: GestureDetector(
                    onTap: () => setState(
                        () => _consents[e.key] = !(_consents[e.key] ?? false)),
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
