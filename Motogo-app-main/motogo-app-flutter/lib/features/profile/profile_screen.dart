import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/logo_header.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../catalog/catalog_provider.dart';
import '../payment/payment_methods_screen.dart';
import 'widgets/profile_field.dart';
import 'widgets/profile_section_title.dart';
import 'widgets/profile_menu_item.dart';
import 'widgets/consent_sheet.dart';
import 'widgets/branches_sheet.dart';
import 'widgets/settings_sheets.dart';

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
        showMotoGoToast(context, icon: '✓', title: t(context).tr('saved'), message: t(context).tr('profileUpdated'));
        ref.invalidate(profileProvider);
      }
    } catch (e) {
      if (await handleAuthError(e)) return;
      if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
    }
  }

  Future<void> _logout() async {
    // Reset booking flow state before logout
    ref.read(bookingDraftProvider.notifier).state = BookingDraft();
    ref.read(bookingMotoProvider.notifier).state = null;
    ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
    await AuthService.signOut();
    if (mounted) {
      showMotoGoToast(context, icon: '✓', title: t(context).tr('logoutTitle'), message: t(context).tr('goodbye'));
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
      error: (_, __) => Scaffold(body: Center(child: Text(t(context).tr('profileLoadError')))),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LogoRow(),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(color: MotoGoColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text(profile?['full_name'] ?? t(context).tr('pilot'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              // Section: Můj účet
              ProfileSectionTitle(title: t(context).tr('myAccount')),
              ProfileMenuItem(icon: '👤', label: t(context).tr('personalInfo'), onTap: () => setState(() => _personalExpanded = !_personalExpanded)),
              if (_personalExpanded) _buildPersonalForm(),
              ProfileMenuItem(icon: '📩', label: t(context).tr('messages'), onTap: () => context.push(Routes.messages)),
              ProfileMenuItem(icon: '📋', label: t(context).tr('documents'), onTap: () => context.push(Routes.docs)),
              ProfileMenuItem(icon: '🧾', label: t(context).tr('invoices'), onTap: () => context.push(Routes.invoices)),
              ProfileMenuItem(icon: '📄', label: t(context).tr('contracts'), onTap: () => context.push(Routes.contracts)),
              ProfileMenuItem(icon: '💳', label: t(context).tr('paymentMethods'), onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const PaymentMethodsScreen(),
                ));
              }),

              const SizedBox(height: 12),
              ProfileSectionTitle(title: t(context).tr('settings')),
              ProfileMenuItem(icon: '📱', label: t(context).tr('permissions'), onTap: () => _showPermissions(context)),
              ProfileMenuItem(icon: '🔔', label: t(context).tr('notifications'), onTap: () => _showConsentSheet(context, 'notif')),
              ProfileMenuItem(icon: '🔒', label: t(context).tr('privacy'), onTap: () => _showConsentSheet(context, 'priv')),
              ProfileMenuItem(icon: '🔑', label: t(context).tr('changePassword'), onTap: () => _showChangePassword(context)),
              ProfileMenuItem(icon: '🌐', label: t(context).tr('language'), onTap: () => _showLanguagePicker(context)),

              const SizedBox(height: 12),
              ProfileSectionTitle(title: t(context).tr('helpAndSupport')),
              ProfileMenuItem(icon: '🆘', label: t(context).sosTitle, onTap: () => context.push(Routes.sos), bgColor: MotoGoColors.redBg),
              ProfileMenuItem(icon: '❓', label: t(context).tr('helpFaq'), onTap: () => launchUrl(Uri.parse('https://motogo24.cz/faq'))),
              ProfileMenuItem(icon: '📍', label: t(context).tr('branchesLabel'), onTap: () => _showBranches(context)),

              const SizedBox(height: 12),
              ProfileSectionTitle(title: t(context).tr('otherSection')),
              ProfileMenuItem(icon: '🚪', label: t(context).logout, onTap: _logout, labelColor: MotoGoColors.red, bgColor: const Color(0xFFFEF2F2)),

              const SizedBox(height: 12),
              Center(child: GestureDetector(
                onTap: () => _showDeleteAccountDialog(context),
                child: Text(t(context).tr('deleteAccountLink'), style: const TextStyle(fontSize: 11, color: MotoGoColors.g400, decoration: TextDecoration.underline)),
              )),
              const SizedBox(height: 8),
              Center(child: Text('MotoGo24 $appVersion', style: const TextStyle(fontSize: 10, color: MotoGoColors.g400, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
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
        ProfileField(ctrl: _nameCtrl, label: t(context).tr('fullNameLabel')),
        ProfileField(ctrl: _phoneCtrl, label: t(context).tr('phone'), type: TextInputType.phone),
        ProfileField(ctrl: _cityCtrl, label: t(context).tr('city')),
        ProfileField(ctrl: _zipCtrl, label: t(context).tr('zip')),
        ProfileField(ctrl: _streetCtrl, label: t(context).tr('streetShort')),
        ProfileField(ctrl: _dobCtrl, label: t(context).tr('dob')),
        ProfileField(ctrl: _licNumCtrl, label: t(context).tr('licenseNumberFull')),
        ProfileField(ctrl: _licExpCtrl, label: t(context).tr('licenseExpiry')),
        ProfileField(ctrl: _licGroupCtrl, label: t(context).tr('licenseCategory')),
        const SizedBox(height: 8),
        ElevatedButton.icon(onPressed: _save, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)), icon: const Icon(Icons.save, size: 16), label: Text(t(context).tr('saveChanges'))),
      ]),
    );
  }

  void _showBranches(BuildContext context) => showBranchesSheet(context);

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t(context).tr('deleteAccountTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(t(context).tr('deleteAccountDesc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(context).cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final user = MotoGoSupabase.currentUser;
              if (user == null) return;
              try {
                await MotoGoSupabase.client.rpc('delete_customer_account', params: {'p_user_id': user.id});
                await AuthService.signOut();
                if (mounted) {
                  showMotoGoToast(context, icon: '✓', title: t(context).tr('accountDeleted'), message: t(context).tr('goodbye'));
                  context.go(Routes.login);
                }
              } catch (e) {
                if (await handleAuthError(e)) return;
                if (mounted) showMotoGoToast(context, icon: '✗', title: t(context).error, message: '$e');
              }
            },
            child: Text(t(context).tr('deleteAccountBtn'), style: const TextStyle(color: MotoGoColors.red)),
          ),
        ],
      ),
    );
  }

  void _showConsentSheet(BuildContext context, String section) {
    showModalBottomSheet(context: context, builder: (_) => ConsentSheet(section: section));
  }

  void _showLanguagePicker(BuildContext context) => showLanguagePickerSheet(context, ref);

  void _showChangePassword(BuildContext context) => showChangePasswordSheet(context);

  void _showPermissions(BuildContext context) => context.push(Routes.permissions);
}
