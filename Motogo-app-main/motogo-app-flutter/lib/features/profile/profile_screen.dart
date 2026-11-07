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
import '../../core/feature_flags.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/date_dropdown_field.dart';
import '../../core/widgets/error_feedback.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../home/nickname_provider.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../catalog/catalog_provider.dart';
import '../loyalty/loyalty_rank_card.dart';
import '../loyalty/loyalty_provider.dart';
import '../payment/payment_methods_screen.dart';
import '../messages/messages_provider.dart' show adminUnreadCountProvider;
import '../sos/sos_provider.dart' show hasActiveRentalProvider;
import 'widgets/profile_field.dart';
import 'widgets/profile_section_title.dart';
import 'widgets/profile_menu_item.dart';
import 'widgets/consent_sheet.dart';
import 'widgets/settings_sheets.dart';
import '../../core/v2/flag/v2_scope.dart';
import 'v2/profile_booking_fix_v2.dart';
import 'v2/profile_hub_v2.dart';
import 'v2/profile_personal_v2.dart' show PfFormData;
import 'v2/profile_groups_v2.dart' show PfGroupActions;
import 'v2/sheets/profile_dialogs_v2.dart';

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
      Object? groupError;
      try {
        await MotoGoSupabase.client
            .rpc('set_my_license_group', params: {'p_groups': groupTokens});
      } catch (e) {
        // Neblokuj uložení ostatních údajů, ale NEtvrď „Uloženo" — skupina ŘP
        // rozhoduje o vydání kódů ke dveřím.
        groupError = e;
      }
      if (mounted) {
        ref.invalidate(profileProvider);
        if (groupError != null) {
          showErrorSnack(context, t(context).tr('eoLicenseGroupNotSaved'), groupError,
              where: 'profile_license_group', onRetry: _save);
        } else {
          showMotoGoToast(context, icon: '✓', title: t(context).tr('saved'), message: t(context).tr('profileUpdated'));
        }
      }
    } catch (e) {
      if (await handleAuthError(e)) return;
      if (mounted) {
        showErrorSnack(context, t(context).tr('eoProfileSaveFail'), e,
            where: 'profile_save', onRetry: _save);
      }
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

    // Menu (Zprávy, Doklady, Jazyk, Oprávnění, Odhlásit, Kontakt) je vidět
    // VŽDY — i během načítání a při chybě (dřív „Chyba načítání profilu" bez
    // cesty dál). Osobní údaje jdou upravit, až když je profil načtený.
    return profileAsync.when(
      data: (profile) {
        _fillFromProfile(profile);
        return _buildProfile(context, profile);
      },
      loading: () => _buildProfile(context, profileAsync.valueOrNull, loading: true),
      error: (e, _) => _buildProfile(context, profileAsync.valueOrNull, error: e),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic>? profile,
      {bool loading = false, Object? error}) {
    final ready = !loading && error == null && _loaded;
    // Akce sdílené starým i v2 stromem (kill-switch app_v2_ui) — těla beze změny.
    void onPersonal() {
                // Bez načteného profilu by formulář byl prázdný a uložení by
                // údaje smazalo → nejdřív načíst.
                if (!ready) {
                  if (error != null) {
                    showErrorSnack(context, t(context).tr('eoProfileLoadFail'), error,
                        onRetry: () => ref.invalidate(profileProvider));
                  } else {
                    showMotoGoToast(context,
                        icon: '⏳', title: t(context).tr('eoProfileStillLoading'));
                  }
                  return;
                }
                setState(() => _personalExpanded = !_personalExpanded);
              }
    void onPaymentMethods() {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const PaymentMethodsScreen(),
                ));
              }
    void onFaq() => launchUrl(Uri.parse(WebLinks.faq(ref.read(localeProvider).languageCode)), mode: LaunchMode.externalApplication);

    // v2 vzhled (PLAN §2.5.1): stejný stav, stejné ovladače a akce.
    if (MgV2.on(context)) {
      // Pushed z formuláře rezervace („Doplnit v profilu"): zpět + doplnění.
      final back = pfPushedBack(context);
      return ProfileHubV2View(
        onBack: back,
        bookingFix: back != null && pfBookingFixRequested(context),
        profile: profile,
        loading: loading,
        error: error,
        ready: ready,
        personalExpanded: _personalExpanded,
        onRetry: () => ref.invalidate(profileProvider),
        onTogglePersonal: onPersonal,
        onPaymentMethods: onPaymentMethods,
        version: appVersion,
        form: PfFormData(
          name: _nameCtrl, email: _emailCtrl, phone: _phoneCtrl, city: _cityCtrl, zip: _zipCtrl,
          street: _streetCtrl, country: _countryCtrl, idNum: _idNumCtrl, licNum: _licNumCtrl,
          dob: _dob,
          licExp: _licExp,
          dobFirstYear: DateTime.now().year - 100,
          dobLastYear: (_dob != null && _dob!.year > DateTime.now().year - 18)
              ? _dob!.year
              : DateTime.now().year - 18,
          // Propadlý ŘP z dřívějška zůstane v nabídce (jinak assert dropdownu).
          licFirstYear: (_licExp != null && _licExp!.year < DateTime.now().year)
              ? _licExp!.year
              : DateTime.now().year,
          licLastYear: DateTime.now().year + 20,
          licCategories: _licCategories,
          licOptions: _licCategoryOptions,
          onDob: (d) => setState(() => _dob = d),
          onLicExp: (d) => setState(() => _licExp = d),
          onToggleCategory: (cat) => setState(() {
            if (_licCategories.contains(cat)) {
              _licCategories.remove(cat);
            } else {
              _licCategories.add(cat);
            }
          }),
          onSave: _save,
        ),
        actions: PfGroupActions(
          onPermissions: () => _showPermissions(context),
          onNotif: () => _showConsentSheet(context, 'notif'),
          onPrivacy: () => _showConsentSheet(context, 'priv'),
          onPassword: () => _showChangePassword(context),
          onLanguage: () => _showLanguagePicker(context),
          onCurrency: () => _showCurrencyPicker(context),
          onFaq: onFaq,
          onLogout: _logout,
          onDelete: () => _showDeleteAccountDialog(context),
        ),
      );
    }

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
                  // Viditelná šipka zpět (sem se chodí přes `go` z hlavičky Domů).
                  Row(children: [
                    MgBackArrow(onTap: () => context.backOr(Routes.home)),
                    const SizedBox(width: 4),
                    const Expanded(child: LogoRow()),
                  ]),
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
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(color: MotoGoColors.green),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MgErrorView(
                    compact: true,
                    error: error,
                    what: t(context).tr('eoProfileLoadFail'),
                    onRetry: () => ref.invalidate(profileProvider),
                  ),
                ),
              // Věrnostní rank — sleva 1–20 % JEN pro rezervace v aplikaci.
              // Karta se sama skryje (vč. titulku), dokud backend rank nevrací.
              const LoyaltyRankCard(),

              // Pobočky (Mezná + Velké Němčice, texty z Velína) — na místě e-shopu.
              // E-shop je dočasně skrytý (2026-10-01); vrátí ho flag `eshop_visible`.
              ProfileMenuItem(icon: '📍', label: t(context).tr('branchesLabel'), onTap: () => context.push(Routes.branchesInfo)),
              if (ref.watch(eshopVisibleProvider).valueOrNull ?? false)
                ProfileMenuItem(icon: '🛒', label: t(context).tr('eshopMenu'), onTap: () => context.push(Routes.shop)),

              const SizedBox(height: 12),
              // Section: Můj účet
              ProfileSectionTitle(title: t(context).tr('myAccount')),
              ProfileMenuItem(icon: '👤', label: t(context).tr('personalInfo'), onTap: onPersonal),
              if (_personalExpanded && ready) _buildPersonalForm(),
              ProfileMenuItem(icon: '📩', label: t(context).tr('messages'), badge: ref.watch(adminUnreadCountProvider), onTap: () => context.push(Routes.messages)),
              ProfileMenuItem(icon: '📋', label: t(context).tr('documents'), onTap: () => context.push(Routes.docs)),
              ProfileMenuItem(icon: '🧾', label: t(context).tr('invoices'), onTap: () => context.push(Routes.invoices)),
              ProfileMenuItem(icon: '📄', label: t(context).tr('contracts'), onTap: () => context.push(Routes.contracts)),
              ProfileMenuItem(icon: '💳', label: t(context).tr('paymentMethods'), onTap: onPaymentMethods),

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
              if (ref.watch(hasActiveRentalProvider))
                ProfileMenuItem(icon: '🆘', label: t(context).sosTitle, onTap: () => context.push(Routes.sos), bgColor: MotoGoColors.redBg),
              ProfileMenuItem(icon: '❓', label: t(context).tr('helpFaq'), onTap: onFaq),

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
          // Půjčovna jen od 18 let (brána přístupových kódů 2026-10-10);
          // už uložený mladší ročník zůstane v nabídce (jinak assert dropdownu).
          lastYear: (_dob != null && _dob!.year > DateTime.now().year - 18)
              ? _dob!.year
              : DateTime.now().year - 18,
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

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        Future<void> onDelete() async {
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
                if (mounted) {
                  showErrorSnack(context, t(context).tr('eoDeleteAccountWhat'), e,
                      where: 'delete_account');
                }
              }
        }
        // v2 vzhled dialogu (T6): stejné texty, Zrušit = zavřít, akce = onDelete.
        if (MgV2.on(ctx)) {
          return DestructiveDialogV2(
            title: t(context).tr('deleteAccountTitle'),
            body: t(context).tr('deleteAccountDesc'),
            cancelLabel: t(context).cancel,
            deleteLabel: t(context).tr('deleteAccountBtn'),
            onCancel: () => Navigator.pop(ctx),
            onDelete: onDelete,
          );
        }
        return AlertDialog(
        title: Text(t(context).tr('deleteAccountTitle'), style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(t(context).tr('deleteAccountDesc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(context).cancel)),
          TextButton(
            onPressed: onDelete,
            child: Text(t(context).tr('deleteAccountBtn'), style: const TextStyle(color: MotoGoColors.red)),
          ),
        ],
      );
      },
    );
  }

  void _showConsentSheet(BuildContext context, String section) {
    showModalBottomSheet(context: context, isScrollControlled: MgV2.peek(context), builder: (_) => ConsentSheet(section: section));
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
