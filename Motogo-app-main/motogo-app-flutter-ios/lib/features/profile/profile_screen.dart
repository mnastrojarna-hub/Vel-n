import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/web_links.dart';
import '../../core/widgets/logo_header.dart';
import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/date_dropdown_field.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../home/nickname_provider.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../catalog/catalog_provider.dart';
import '../loyalty/loyalty_rank_card.dart';
import '../loyalty/loyalty_provider.dart';
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
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _idNumCtrl = TextEditingController();
  final _licNumCtrl = TextEditingController();
  DateTime? _dob;
  DateTime? _licExp;
  final Set<String> _licCategories = {};
  bool _loaded = false;
  // Osobní údaje jsou ve výchozím stavu sbalené (klepnutím se rozbalí).
  // Problém „nejsou vidět" způsobila registrace, která údaje neukládala — to
  // je opraveno zápisem přes upsert; sekce tedy zůstává sbalená jako dřív.
  bool _personalExpanded = false;

  /// Available driver-license categories offered in the picker.
  static const _licCategoryOptions = ['AM', 'A1', 'A2', 'A', 'B'];

  @override
  void initState() {
    super.initState();
    // Vynuť čerstvé načtení profilu z DB při každém otevření. Hned po registraci
    // byl `profileProvider` naplněn JEŠTĚ PŘED zápisem profilu (RPC běží až po
    // vzniku session), takže cache mohla držet prázdná pole, i když data v DB
    // už jsou (proto „ve Velíně to je, v appce ne"). Invalidace → provider jde
    // do loading → `_fillFromProfile` se nezavolá na prázdná data → po dotažení
    // se vyplní čerstvými hodnotami.
    ref.invalidate(profileProvider);
    ref.invalidate(loyaltyStatusProvider);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose(); _cityCtrl.dispose();
    _zipCtrl.dispose(); _streetCtrl.dispose(); _countryCtrl.dispose();
    _idNumCtrl.dispose(); _licNumCtrl.dispose();
    super.dispose();
  }

  void _fillFromProfile(Map<String, dynamic>? profile) {
    if (profile == null || _loaded) return;
    _loaded = true;
    _nameCtrl.text = profile['full_name'] ?? '';
    _emailCtrl.text = profile['email'] ?? '';
    _phoneCtrl.text = profile['phone'] ?? '';
    _cityCtrl.text = profile['city'] ?? '';
    _zipCtrl.text = profile['zip'] ?? '';
    _streetCtrl.text = profile['street'] ?? '';
    _countryCtrl.text = profile['country'] ?? '';
    _idNumCtrl.text = profile['id_number'] ?? '';
    _licNumCtrl.text = profile['license_number'] ?? '';
    _dob = _parseDate(profile['date_of_birth']);
    _licExp = _parseDate(profile['license_expiry']);
    final groups = profile['license_group'];
    final raw = groups is List ? groups : (groups == null ? const [] : '$groups'.split(RegExp(r'[,\s]+')));
    _licCategories
      ..clear()
      ..addAll(raw.map((g) => '$g'.trim().toUpperCase()).where((g) => g.isNotEmpty));
  }

  /// Parses an ISO date string (yyyy-MM-dd) coming from Supabase.
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }


  /// ISO yyyy-MM-dd for storage in a Postgres `date` column.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      // Skupina ŘP (license_group[]) je ENUM pole — PostgREST ho z prostého
      // JSON pole NEUMÍ přetypovat, takže by CELÝ update spadl a neuložilo by se
      // nic. Proto ostatní pole uložíme běžným updatem a skupinu ŘP zvlášť přes
      // SECURITY DEFINER RPC `set_my_license_group`. Datumy posíláme jako ISO
      // (yyyy-MM-dd) nebo null.
      final groupTokens = _licCategories.toList();
      await MotoGoSupabase.client.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'zip': _zipCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'date_of_birth': _dob == null ? null : _isoDate(_dob!),
        // Číslo dokladu totožnosti (OP nebo pas) — ručně zadané se uloží do
        // profilu a vytiskne do smlouvy. (Ověření přes OCR/fotku řeší sken.)
        'id_number': _idNumCtrl.text.trim(),
        'license_number': _licNumCtrl.text.trim(),
        'license_expiry': _licExp == null ? null : _isoDate(_licExp!),
      }).eq('id', user.id);
      try {
        await MotoGoSupabase.client
            .rpc('set_my_license_group', params: {'p_groups': groupTokens});
      } catch (_) {/* RPC ještě nenasazená / dočasná chyba — neblokuj uložení */}
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
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(color: MotoGoColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                          child: Text(profile?['full_name'] ?? t(context).tr('pilot'),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Duplicitní rychlá úprava přezdívky pilota i z hlavičky profilu.
                      _NicknameChip(fullName: profile?['full_name'] as String?),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: [
              // Věrnostní rank — sleva 1–20 % JEN pro rezervace v aplikaci.
              // Karta se sama skryje (vč. titulku), dokud backend rank nevrací.
              const LoyaltyRankCard(),

              // E-shop — přesunuto ze spodní lišty do menu (na jeho místo přišly Trasy)
              ProfileMenuItem(icon: '🛒', label: t(context).tr('eshopMenu'), onTap: () => context.push(Routes.shop)),

              const SizedBox(height: 12),
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
              ProfileMenuItem(icon: '💱', label: t(context).tr('currency'), onTap: () => _showCurrencyPicker(context)),

              const SizedBox(height: 12),
              ProfileSectionTitle(title: t(context).tr('helpAndSupport')),
              ProfileMenuItem(icon: '🆘', label: t(context).sosTitle, onTap: () => context.push(Routes.sos), bgColor: MotoGoColors.redBg),
              ProfileMenuItem(icon: '❓', label: t(context).tr('helpFaq'), onTap: () => launchUrl(Uri.parse(WebLinks.faq(ref.read(localeProvider).languageCode)), mode: LaunchMode.externalApplication)),
              ProfileMenuItem(icon: '📍', label: t(context).tr('branchesLabel'), onTap: () => _showBranches(context)),

              const SizedBox(height: 12),
              ProfileSectionTitle(title: t(context).tr('otherSection')),
              ProfileMenuItem(icon: '🚪', label: t(context).logout, onTap: _logout, labelColor: MotoGoColors.red, bgColor: const Color(0xFFFEF2F2)),
              ProfileMenuItem(icon: '🗑️', label: t(context).tr('deleteAccountBtn'), onTap: () => _showDeleteAccountDialog(context), labelColor: MotoGoColors.red, bgColor: const Color(0xFFFEF2F2)),

              const SizedBox(height: 12),
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
        // E-mail je přihlašovací identita → jen ke čtení (mění se přes podporu).
        ProfileField(ctrl: _emailCtrl, label: t(context).email, readOnly: true),
        ProfileField(ctrl: _phoneCtrl, label: t(context).tr('phone'), type: TextInputType.phone),
        ProfileField(ctrl: _cityCtrl, label: t(context).tr('city')),
        ProfileField(ctrl: _zipCtrl, label: t(context).tr('zip')),
        ProfileField(ctrl: _streetCtrl, label: t(context).tr('streetShort')),
        ProfileField(ctrl: _countryCtrl, label: t(context).tr('countryLabel')),
        DateDropdownField(
          label: t(context).tr('dob'),
          value: _dob,
          firstYear: DateTime.now().year - 100,
          lastYear: DateTime.now().year - 15,
          yearsDescending: true,
          onChanged: (d) => setState(() => _dob = d),
        ),
        ProfileField(ctrl: _idNumCtrl, label: t(context).tr('idNumberFull')),
        ProfileField(ctrl: _licNumCtrl, label: t(context).tr('licenseNumberFull')),
        DateDropdownField(
          label: t(context).tr('licenseExpiry'),
          value: _licExp,
          firstYear: DateTime.now().year,
          lastYear: DateTime.now().year + 20,
          onChanged: (d) => setState(() => _licExp = d),
        ),
        _categoryPicker(),
        const SizedBox(height: 8),
        ElevatedButton.icon(onPressed: _save, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)), icon: const Icon(Icons.save, size: 16), label: Text(t(context).tr('saveChanges'))),
      ]),
    );
  }

  /// Multi-select chips for the driver-license categories (stored as text[]).
  Widget _categoryPicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(context).tr('licenseCategory'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _licCategoryOptions.map((cat) {
              final selected = _licCategories.contains(cat);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _licCategories.remove(cat);
                  } else {
                    _licCategories.add(cat);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? MotoGoColors.greenDarker : MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? MotoGoColors.greenDarker : MotoGoColors.g200,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: selected ? Colors.white : MotoGoColors.black,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
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
                // RPC vrací JSONB — při aktivní/nadcházející rezervaci NEHODÍ
                // výjimku, ale vrátí {"error":"active_bookings",...}. Bez kontroly
                // appka dřív tvrdila „Účet smazán", ale auth.users zůstal → účet
                // šel hned znovu přihlásit. Proto výsledek explicitně ověřujeme.
                final res = await MotoGoSupabase.client
                    .rpc('delete_customer_account', params: {'p_user_id': user.id});
                final result = res is Map ? Map<String, dynamic>.from(res) : null;
                final ok = result?['success'] == true;
                if (!ok) {
                  final err = result?['error']?.toString();
                  final msg = err == 'active_bookings'
                      ? t(context).tr('deleteAccountHasBookings')
                      : t(context).tr('deleteAccountFailed');
                  if (mounted) {
                    showMotoGoToast(context, icon: '⚠️',
                        title: t(context).tr('deleteAccountTitle'), message: msg);
                  }
                  return;
                }
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

  void _showLanguagePicker(BuildContext context) => showLanguagePickerSheet(context);

  void _showCurrencyPicker(BuildContext context) => showCurrencyPickerSheet(context);

  void _showChangePassword(BuildContext context) => showChangePasswordSheet(context);

  void _showPermissions(BuildContext context) => context.push(Routes.permissions);
}

/// Tappable „PILOT: <přezdívka> ✎" chip v hlavičce profilu — otevře sdílený
/// dialog pro úpravu přezdívky (stejný jako na domovské obrazovce).
class _NicknameChip extends ConsumerWidget {
  final String? fullName;
  const _NicknameChip({required this.fullName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(nicknameProvider);
    final display = nickname ?? extractFirstName(fullName);
    final rankColor = ref.watch(loyaltyStatusProvider).valueOrNull?.color
        ?? MotoGoColors.green;
    return PressableScale(
      pressedScale: 0.9,
      onTap: () => showNicknameDialog(context, ref, fullName: fullName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: rankColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: rankColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(color: rankColor.withValues(alpha: 0.35), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(context).tr('homePilotLabel'),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
            Text(
              display,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 12, color: rankColor),
          ],
        ),
      ),
    );
  }
}
