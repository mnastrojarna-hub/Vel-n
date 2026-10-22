// v2 Profil sub-screens part 2 (PLAN §5.3, area "profile"): Oprávnění,
// Pobočky, Pobočka, Věrnostní ranky and every settings sheet / dialog
// (consents, password, language, currency, nickname, delete, document kind,
// new conversation, AI photo, loyalty program).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

import '../support/fakes_home.dart' show kLoyalty3, loyaltyAt, mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/fakes_profile_sub.dart';
import '../support/profile_matrix.dart';
import '../support/v2_harness.dart';

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

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerProfileStrings();
    mockPathProvider();
  });

  pfMatrix([
    PfCase('permissions', 'loading', () => _permsView(loading: true), () => const [], settle: false),
    PfCase('permissions', 'ok', () => _permsView(), () => const []),
    PfCase('permissions', 'required_denied', () => _permsView(required: true), () => const [], level: 10),
    PfCase('permissions', 'no_bio', () => _permsView(bio: false), () => const []),
    PfCase('branches', 'list', () => const BranchesInfoScreen(), branchesOverrides),
    PfCase('branch', 'mezna', () => const BranchDetailScreen(index: 0), branchesOverrides),
    PfCase('branch', 'vn_open', () => const BranchDetailScreen(index: 1), branchesOverrides, after: _expandAll, level: 15),
    for (final l in const [1, 6, 10, 13, 14, 16, 17, 18, 20])
      PfCase('loyalty', 'rank$l', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: l == 3 ? kLoyalty3 : loyaltyAt(l)), level: l),
    PfCase('loyalty', 'guest', () => const LoyaltyScreenV2(), () => loyaltyOverrides(), level: 0),
    PfCase('loyalty', 'loading', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: kLoyalty3, loading: true), settle: false),
    PfCase('loyalty', 'error', () => const LoyaltyScreenV2(), () => loyaltyOverrides(status: kLoyalty3, error: true)),
    PfCase('sheet', 'consent_notif',
        () => pfLauncher((c) => showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => const ConsentSheet(section: 'notif'))),
        () => profileOverrides(), after: _open),
    PfCase('sheet', 'consent_priv_locked',
        () => pfLauncher((c) => showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => const ConsentSheet(section: 'priv'))),
        () => profileOverrides(reservations: activeRental()), after: _open),
    PfCase('sheet', 'password', () => pfLauncher(showChangePasswordSheet), () => const [], after: _open),
    PfCase('sheet', 'password_error', () => pfLauncher(showChangePasswordSheet), () => const [], after: _submitShort),
    PfCase('sheet', 'language', () => pfLauncher(showLanguagePickerSheet), () => const [], after: _open),
    PfCase('sheet', 'currency', () => pfLauncher(showCurrencyPickerSheet), () => const [], after: _open),
    PfCase('sheet', 'nickname', _nickLauncher, () => const [], after: _open),
    PfCase(
        'sheet',
        'delete_account',
        () => pfLauncher((c) => showDialog(
            context: c,
            builder: (ctx) => DestructiveDialogV2(
                title: 'Smazat účet?',
                body: 'Tato akce je nevratná. Všechna data, rezervace a dokumenty budou trvale smazány.',
                cancelLabel: 'Zrušit',
                deleteLabel: 'Smazat účet',
                onCancel: () {},
                onDelete: () {}))),
        () => const [],
        after: _open),
    PfCase('sheet', 'doc_kind', () => pfLauncher(pickGalleryDocKind), () => const [], after: _open),
    PfCase(
        'sheet',
        'new_thread',
        () => pfLauncher((c) => showModalBottomSheet(
            context: c,
            isScrollControlled: true,
            builder: (_) => NewThreadSheetV2View(
                controller: TextEditingController(), onSubmitted: (_) {}, onSend: () {}, onClose: () {}))),
        () => const [],
        after: _open),
    PfCase('sheet', 'ai_photo',
        () => pfLauncher((c) => showModalBottomSheet(context: c, builder: (_) => AiPhotoSheetV2(onCamera: () {}, onGallery: () {}))),
        () => const [], after: _open),
    PfCase('sheet', 'loyalty_info', () => pfLauncher(showLoyaltyInfoSheetV2), () => const [], after: _open),
  ]);
}
