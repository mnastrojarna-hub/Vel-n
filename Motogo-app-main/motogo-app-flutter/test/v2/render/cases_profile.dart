// verify:render cases — Profil v2 hub (profile_hub_test.dart) and its
// sub-screens / sheets / dialogs (profile_more_test.dart): Oprávnění,
// Pobočky, Pobočka, Věrnostní ranky, consents, password, language,
// currency, nickname, delete account, document kind, new conversation,
// AI photo, loyalty program.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/native/permission_service.dart' show PermissionInfo;
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/features/branches/branch_detail_screen.dart';
import 'package:motogo_app/features/branches/branches_info_screen.dart';
import 'package:motogo_app/features/branches/v2/branches_v2_parts.dart';
import 'package:motogo_app/features/documents/docs_gate_widgets.dart';
import 'package:motogo_app/features/home/nickname_provider.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_info_sheet_v2.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_screen_v2.dart';
import 'package:motogo_app/features/messages/v2/ai_photo_sheet_v2.dart';
import 'package:motogo_app/features/messages/v2/new_thread_sheet_v2.dart';
import 'package:motogo_app/features/profile/v2/permissions_view_v2.dart';
import 'package:motogo_app/features/profile/v2/sheets/profile_dialogs_v2.dart';
import 'package:motogo_app/features/profile/widgets/consent_sheet.dart';
import 'package:motogo_app/features/profile/widgets/settings_sheets.dart';

import '../support/fakes_home.dart' show kLoyalty3, loyaltyAt;
import '../support/fakes_profile.dart';
import '../support/fakes_profile_sub.dart';
import '../support/profile_harness.dart';
import '../support/profile_matrix.dart' show pfLauncher, pfTap;
import 'render_harness.dart';

const _perms = [
  PermissionInfo(key: 'location', icon: '', title: 'permLocationTitle', desc: 'permLocationDesc', granted: true),
  PermissionInfo(key: 'camera', icon: '', title: 'permCameraTitle', desc: 'permCameraDesc', granted: false),
  PermissionInfo(key: 'notifications', icon: '', title: 'permNotifTitle', desc: 'permNotifDesc', granted: true),
];

Widget _permsView({bool loading = false, bool required = false, bool bio = true}) => PermissionsViewV2(
      perms: loading ? null : [for (final p in _perms) (p, required)],
      requiredActive: required,
      bioAvailable: bio,
      bioEnabled: required,
      onBack: () {},
      onOpenSettings: () {},
      onBioTap: () {},
      onAllowAll: () {},
    );

Future<void> _open(WidgetTester t) => pfTap(t, find.text('OPEN'));

Future<void> _expandAll(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    final f = find.byType(BranchCollapsibleV2);
    if (i >= f.evaluate().length) break;
    await pfTap(t, f.at(i));
  }
}

Future<void> _submitShort(WidgetTester t) async {
  await _open(t);
  final fields = find.byType(TextField);
  if (fields.evaluate().isEmpty) return;
  await t.enterText(fields.first, '123');
  await t.pump();
  await pfTap(t, find.byType(MgBtnInk));
}

Widget _nickLauncher() => Consumer(builder: (c, ref, _) => pfLauncher((ctx) => showNicknameDialog(ctx, ref, fullName: 'Jan Novák')));

RenderCase _p(String screen, String state, Widget Function() b, List<Override> Function() o,
        {int level = 3, Future<void> Function(WidgetTester)? after, bool loading = false}) =>
    RenderCase('profile', screen, state, b, o, level: level, after: after, loading: loading);

List<RenderCase> profileRenderCases() => [
      _p('hub', 'all_ok', () => const PfHubHarness(), () => profileOverrides()),
      _p('hub', 'docs_missing', () => const PfHubHarness(), () => profileOverrides(docs: PfDocs.missing)),
      _p('hub', 'sos_rental', () => const PfHubHarness(), () => profileOverrides(reservations: activeRental(), loyalty: loyaltyAt(6)), level: 6),
      _p('hub', 'new_customer', () => const PfHubHarness(),
          () => profileOverrides(profile: kProfileNew, docs: PfDocs.none, unread: 0, loyalty: loyaltyAt(1)), level: 1),
      _p('hub', 'loading', () => const PfHubHarness(), () => profileOverrides(profileLoading: true, docs: PfDocs.unknown), loading: true),
      _p('hub', 'error', () => const PfHubHarness(), () => profileOverrides(profileError: true)),
      _p('hub', 'eshop_on', () => const PfHubHarness(), () => profileOverrides(eshop: true, loyalty: loyaltyAt(17), unread: 12), level: 17),
      _p('hub', 'legend', () => const PfHubHarness(), () => profileOverrides(loyalty: loyaltyAt(20)), level: 20),
      _p('hub', 'guest_rank', () => const PfHubHarness(), () => profileOverrides(loyalty: null), level: 0),
      _p('hub', 'form_open', () => const PfHubHarness(expanded: true), () => profileOverrides()),
      // Empty dates → the dropdown hints (Den / Měsíc / Rok …) must fit too.
      _p('hub', 'form_open_new', () => const PfHubHarness(expanded: true),
          () => profileOverrides(profile: kProfileNew, docs: PfDocs.none, unread: 0, loyalty: loyaltyAt(1)), level: 1),
      _p('permissions', 'loading', () => _permsView(loading: true), () => const [], loading: true),
      _p('permissions', 'ok', () => _permsView(), () => const []),
      _p('permissions', 'required_denied', () => _permsView(required: true), () => const [], level: 10),
      _p('permissions', 'no_bio', () => _permsView(bio: false), () => const []),
      _p('branches', 'list', () => const BranchesInfoScreen(), branchesOverrides),
      _p('branch', 'mezna', () => const BranchDetailScreen(index: 0), branchesOverrides),
      _p('branch', 'vn_open', () => const BranchDetailScreen(index: 1), branchesOverrides, after: _expandAll, level: 15),
      for (final l in const [1, 6, 10, 13, 14, 16, 17, 18, 20])
        _p('loyalty', 'rank$l', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: loyaltyAt(l)), level: l),
      _p('loyalty', 'guest', () => const LoyaltyScreenV2(), () => loyaltyOverrides(), level: 0),
      _p('loyalty', 'loading', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: kLoyalty3, loading: true), loading: true),
      _p('loyalty', 'error', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: kLoyalty3, error: true)),
      _p('sheet', 'consent_notif',
          () => pfLauncher((c) => showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => const ConsentSheet(section: 'notif'))),
          () => profileOverrides(), after: _open),
      _p('sheet', 'consent_priv_locked',
          () => pfLauncher((c) => showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => const ConsentSheet(section: 'priv'))),
          () => profileOverrides(reservations: activeRental()), after: _open),
      _p('sheet', 'password', () => pfLauncher(showChangePasswordSheet), () => const [], after: _open),
      _p('sheet', 'password_error', () => pfLauncher(showChangePasswordSheet), () => const [], after: _submitShort),
      _p('sheet', 'language', () => pfLauncher(showLanguagePickerSheet), () => const [], after: _open),
      _p('sheet', 'currency', () => pfLauncher(showCurrencyPickerSheet), () => const [], after: _open),
      _p('sheet', 'nickname', _nickLauncher, () => const [], after: _open),
      _p(
          'sheet',
          'delete_account',
          () => pfLauncher((c) => showDialog(
              context: c,
              builder: (ctx) => DestructiveDialogV2(
                  title: t(ctx).tr('deleteAccountTitle'),
                  body: t(ctx).tr('deleteAccountDesc'),
                  cancelLabel: t(ctx).cancel,
                  deleteLabel: t(ctx).tr('deleteAccountBtn'),
                  onCancel: () {},
                  onDelete: () {}))),
          () => const [],
          after: _open),
      _p('sheet', 'doc_kind', () => pfLauncher(pickGalleryDocKind), () => const [], after: _open),
      _p(
          'sheet',
          'new_thread',
          () => pfLauncher((c) => showModalBottomSheet(
              context: c,
              isScrollControlled: true,
              builder: (_) => NewThreadSheetV2View(controller: TextEditingController(), onSubmitted: (_) {}, onSend: () {}, onClose: () {}))),
          () => const [],
          after: _open),
      _p('sheet', 'ai_photo',
          () => pfLauncher((c) => showModalBottomSheet(context: c, builder: (_) => AiPhotoSheetV2(onCamera: () {}, onGallery: () {}))),
          () => const [], after: _open),
      _p('sheet', 'loyalty_info', () => pfLauncher(showLoyaltyInfoSheetV2), () => const [], after: _open),
    ];
