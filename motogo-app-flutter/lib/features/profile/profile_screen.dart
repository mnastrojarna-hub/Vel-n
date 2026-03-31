import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';

/// Profile screen — mirrors s-profile from templates-done-pages.js.
/// Personal info, docs, invoices, messages, consents, settings, logout.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _licNumCtrl = TextEditingController();
  final _licExpCtrl = TextEditingController();
  final _licGroupCtrl = TextEditingController();
  bool _loaded = false;
  bool _personalExpanded = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _cityCtrl.dispose();
    _zipCtrl.dispose(); _streetCtrl.dispose(); _dobCtrl.dispose();
    _licNumCtrl.dispose(); _licExpCtrl.dispose(); _licGroupCtrl.dispose();
    super.dispose();
  }

  void _fillFromProfile(Map<String, dynamic>? profile) {
    if (profile == null || _loaded) return;
    _loaded = true;
    _nameCtrl.text = profile['full_name'] ?? '';
    _phoneCtrl.text = profile['phone'] ?? '';
    _cityCtrl.text = profile['city'] ?? '';
    _zipCtrl.text = profile['zip'] ?? '';
    _streetCtrl.text = profile['street'] ?? '';
    _dobCtrl.text = profile['date_of_birth'] ?? '';
    _licNumCtrl.text = profile['license_number'] ?? '';
    _licExpCtrl.text = profile['license_expiry'] ?? '';
    final groups = profile['license_group'];
    _licGroupCtrl.text = groups is List ? groups.join(', ') : (groups ?? '');
  }

  Future<void> _save() async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      await MotoGoSupabase.client.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'zip': _zipCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'date_of_birth': _dobCtrl.text.trim(),
        'license_number': _licNumCtrl.text.trim(),
        'license_expiry': _licExpCtrl.text.trim(),
      }).eq('id', user.id);
      if (mounted) {
        showMotoGoToast(context, icon: '✓', title: 'Uloženo', message: 'Profil aktualizován');
        ref.invalidate(profileProvider);
      }
    } catch (e) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: '$e');
    }
  }

  Future<void> _logout() async {
    await AuthService.signOut();
    if (mounted) {
      showMotoGoToast(context, icon: '✓', title: 'Odhlášení', message: 'Nashledanou!');
      context.go(Routes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      data: (profile) {
        _fillFromProfile(profile);
        return _buildProfile(context, profile);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (_, __) => const Scaffold(body: Center(child: Text('Chyba načítání profilu'))),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic>? profile) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 14),
              decoration: const BoxDecoration(
                color: MotoGoColors.dark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 20)))),
                    const SizedBox(width: 10),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('MOTO GO 24', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                      Text('PŮJČOVNA MOTOREK', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 2.5)),
                    ]),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(color: MotoGoColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(profile?['full_name'] ?? 'Pilot', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              // Section: Můj účet
              _SectionTitle(title: 'Můj účet'),
              _MenuItem(icon: '👤', label: 'Osobní údaje', onTap: () => setState(() => _personalExpanded = !_personalExpanded)),
              if (_personalExpanded) _buildPersonalForm(),
              _MenuItem(icon: '📩', label: 'Zprávy z Moto Go', onTap: () => context.push(Routes.messages)),
              _MenuItem(icon: '📋', label: 'Moje doklady', onTap: () => context.push(Routes.docs)),
              _MenuItem(icon: '🧾', label: 'Faktury a vyúčtování', onTap: () => context.push(Routes.invoices)),
              _MenuItem(icon: '📄', label: 'Dokumenty a smlouvy', onTap: () => context.push(Routes.contracts)),
              _MenuItem(icon: '💳', label: 'Platební metody', onTap: () {
                // Payment methods from Part 4
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const _PlaceholderPage('Platební metody'),
                ));
              }),

              const SizedBox(height: 12),
              _SectionTitle(title: 'Nastavení'),
              _MenuItem(icon: '🔔', label: 'Notifikace', onTap: () => _showConsentSheet(context, 'notif')),
              _MenuItem(icon: '🔐', label: 'Biometrické přihlášení', onTap: () {}),
              _MenuItem(icon: '🔒', label: 'Soukromí a souhlasy', onTap: () => _showConsentSheet(context, 'priv')),
              _MenuItem(icon: '🔑', label: 'Změna hesla', onTap: () {}),
              _MenuItem(icon: '🌐', label: 'Jazyk aplikace', onTap: () {}),

              const SizedBox(height: 12),
              _SectionTitle(title: 'Pomoc & Podpora'),
              _MenuItem(icon: '🆘', label: 'SOS — Pomoc na cestě', onTap: () => context.push(Routes.sos), bgColor: const Color(0xFFFEE2E2)),
              _MenuItem(icon: '❓', label: 'Nápověda & FAQ', onTap: () {}),
              _MenuItem(icon: '📍', label: 'Pobočky', onTap: () {}),

              const SizedBox(height: 12),
              _SectionTitle(title: 'Ostatní'),
              _MenuItem(icon: '🚪', label: 'Odhlásit se', onTap: _logout, labelColor: MotoGoColors.red, bgColor: const Color(0xFFFEF2F2)),

              const SizedBox(height: 12),
              Center(child: GestureDetector(
                onTap: () {},
                child: const Text('Smazat účet a všechna data', style: TextStyle(fontSize: 11, color: MotoGoColors.g400, decoration: TextDecoration.underline)),
              )),
              const SizedBox(height: 8),
              const Center(child: Text('MotoGo24 v5.5.4', style: TextStyle(fontSize: 10, color: MotoGoColors.g400, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
      child: Column(children: [
        _Field(ctrl: _nameCtrl, label: 'Jméno a příjmení'),
        _Field(ctrl: _phoneCtrl, label: 'Telefon', type: TextInputType.phone),
        _Field(ctrl: _cityCtrl, label: 'Obec / město'),
        _Field(ctrl: _zipCtrl, label: 'PSČ'),
        _Field(ctrl: _streetCtrl, label: 'Ulice a č.p.'),
        _Field(ctrl: _dobCtrl, label: 'Datum narození'),
        _Field(ctrl: _licNumCtrl, label: 'Č. řidičského průkazu'),
        _Field(ctrl: _licExpCtrl, label: 'Platnost ŘP do'),
        _Field(ctrl: _licGroupCtrl, label: 'Kategorie ŘP'),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: const Text('Uložit změny')),
      ]),
    );
  }

  void _showConsentSheet(BuildContext context, String section) {
    showModalBottomSheet(context: context, builder: (_) => _ConsentSheet(section: section));
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl; final String label; final TextInputType type;
  const _Field({required this.ctrl, required this.label, this.type = TextInputType.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(controller: ctrl, keyboardType: type, decoration: InputDecoration(labelText: label)),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
  );
}

class _MenuItem extends StatelessWidget {
  final String icon; final String label; final VoidCallback onTap;
  final Color? labelColor; final Color? bgColor;
  const _MenuItem({required this.icon, required this.label, required this.onTap, this.labelColor, this.bgColor});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: bgColor ?? MotoGoColors.g100, borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 18)))),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: labelColor ?? MotoGoColors.black))),
        const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
      ]),
    ),
  );
}

class _ConsentSheet extends ConsumerStatefulWidget {
  final String section;
  const _ConsentSheet({required this.section});
  @override
  ConsumerState<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends ConsumerState<_ConsentSheet> {
  Map<String, bool> _consents = {};
  bool _loading = true;

  static const _notifKeys = {'consent_push': 'Push notifikace', 'consent_email': 'Email', 'consent_sms': 'SMS', 'consent_whatsapp': 'WhatsApp', 'marketing_consent': 'Marketing'};
  static const _privKeys = {'consent_vop': 'VOP', 'consent_gdpr': 'GDPR', 'consent_data_processing': 'Zpracování dat', 'consent_contract': 'Smlouva', 'consent_photo': 'Foto'};

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
      _consents = { for (final k in keys.keys) k: profile[k] == true };
      _loading = false;
    });
  }

  Future<void> _save() async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    await MotoGoSupabase.client.from('profiles').update(_consents).eq('id', user.id);
    if (mounted) {
      showMotoGoToast(context, icon: '✓', title: 'Uloženo', message: 'Nastavení bylo uloženo');
      ref.invalidate(profileProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.section == 'notif' ? _notifKeys : _privKeys;
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.section == 'notif' ? 'Notifikace' : 'Soukromí a souhlasy',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
        const SizedBox(height: 16),
        if (_loading) const CircularProgressIndicator(color: MotoGoColors.green)
        else ...keys.entries.map((e) => SwitchListTile(
          title: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          value: _consents[e.key] ?? false,
          activeColor: MotoGoColors.green,
          onChanged: (v) => setState(() => _consents[e.key] = v),
        )),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _save, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: const Text('Uložit')),
      ]),
    ));
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage(this.title);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), backgroundColor: MotoGoColors.dark),
    body: const Center(child: Text('Připraveno v Parts 4')),
  );
}
