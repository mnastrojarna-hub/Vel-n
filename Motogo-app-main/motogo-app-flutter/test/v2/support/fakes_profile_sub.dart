// Fixtures for the Profil v2 sub-screen tests: messages, threads, invoices,
// contracts, document status, loyalty ladder, leaderboard flag, branches.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/features/branches/branches_info_provider.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_models.dart';
import 'package:motogo_app/features/documents/document_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_palette.dart' show kRankOldSeedHex;
import 'package:motogo_app/features/loyalty/loyalty_levels_provider.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/loyalty/rank_names.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';

import 'fakes_home.dart' show day, kMotos;
import 'fakes_profile.dart' show kGateMissing;

final _now = DateTime(2026, 10, 16, 9, 41);

List<AdminMessage> adminMsgs() => [
      AdminMessage(
          id: 'm1', title: 'Sezóna 2027 je otevřená', type: 'voucher', createdAt: _now,
          message: 'Rezervuj si termín včas — první víkendy v dubnu bývají rychle pryč. Sleva za věrnost ti zůstává.'),
      AdminMessage(
          id: 'm2', title: 'Odpověď k SOS', type: 'sos_response', read: true, createdAt: _now.subtract(const Duration(days: 2)),
          message: 'Technik je na cestě, dorazí do 45 minut. Zůstaň prosím u motorky a měj telefon u sebe. '
              'Kdyby se cokoliv změnilo, napiš nám sem nebo zavolej na +420 774 256 271. Děkujeme za trpělivost.'),
      AdminMessage(id: 'm3', title: 'Kódy k vyzvednutí', type: 'door_codes', read: true, createdAt: _now.subtract(const Duration(days: 9))),
    ];

List<MessageThread> threads() => [
      MessageThread(
        id: 't1', subject: 'SOS: Defekt pneumatiky u Jihlavy', channel: 'app', status: 'open',
        createdAt: _now.subtract(const Duration(days: 1)), lastMessageAt: _now,
        messages: [
          Message(id: 'a', content: 'Dobrý den, píchl jsem zadní kolo.', direction: 'customer', createdAt: _now.subtract(const Duration(hours: 2))),
          Message(id: 'b', content: 'Posíláme náhradní motorku, technik je na cestě a bude u vás zhruba za 45 minut.', direction: 'admin', createdAt: _now),
        ],
      ),
      MessageThread(
        id: 't2', subject: 'Dotaz k výbavě spolujezdce', channel: 'app', status: 'closed',
        createdAt: _now.subtract(const Duration(days: 20)),
        messages: [
          Message(id: 'c', content: 'Mají helmy i interkom?', direction: 'customer', createdAt: _now.subtract(const Duration(days: 20))),
          Message(id: 'd', content: 'Ano, interkom zapůjčíme zdarma.', direction: 'admin', readAt: _now, createdAt: _now.subtract(const Duration(days: 19))),
        ],
      ),
    ];

List<Override> messagesOverrides({
  bool notesEmpty = false,
  bool notesLoading = false,
  bool notesError = false,
  bool threadsEmpty = false,
  bool threadsError = false,
  int unread = 1,
}) =>
    [
      adminMessagesProvider.overrideWith((ref) {
        if (notesLoading) return StreamController<List<AdminMessage>>().stream;
        if (notesError) return Stream<List<AdminMessage>>.error(Exception('SocketException: Failed host lookup'));
        return Stream.value(notesEmpty ? const [] : adminMsgs());
      }),
      threadsProvider.overrideWith((ref) {
        if (threadsError) return Stream<List<MessageThread>>.error(Exception('timeout'));
        return Stream.value(threadsEmpty ? const [] : threads());
      }),
      adminUnreadCountProvider.overrideWithValue(unread),
    ];

List<UserInvoice> invoices() => [
      UserInvoice(id: 'i1', number: 'ZF-2026-0142', type: 'advance', total: 12027, createdAt: DateTime(2026, 9, 30)),
      UserInvoice(id: 'i2', number: 'DD-2026-0101', type: 'payment_receipt', total: 12027, createdAt: DateTime(2026, 10, 2)),
      UserInvoice(id: 'i3', number: 'DB-2026-0007', type: 'credit_note', total: -1500, createdAt: DateTime(2026, 10, 5)),
      UserInvoice(id: 'i4', type: 'final', total: 8450, createdAt: DateTime(2025, 6, 14)),
    ];

List<UserDocument> contracts() => [
      UserDocument(id: 'd1', type: 'contract', fileName: 'Nájemní smlouva #A1B2C3D4', bookingId: 'b1', createdAt: day(-9)),
      UserDocument(id: 'd2', type: 'protocol', fileName: 'Předávací protokol #A1B2C3D4', bookingId: 'b1', createdAt: day(-2)),
      UserDocument(id: 'd3', type: 'protocol_damage', bookingId: 'b0', createdAt: DateTime(2025, 7, 1)),
    ];

List<Override> docListOverrides({bool empty = false, bool loading = false, bool error = false}) => [
      invoicesProvider.overrideWith((ref) async {
        if (loading) await Completer<void>().future;
        if (error) throw Exception('SocketException: Failed host lookup');
        return empty ? const <UserInvoice>[] : invoices();
      }),
      contractsProvider.overrideWith((ref) async {
        if (loading) await Completer<void>().future;
        if (error) throw Exception('timeout');
        return empty ? const <UserDocument>[] : contracts();
      }),
    ];

enum DocsState { ok, missing, idOnly, none, loading, error }

List<Override> docsStatusOverrides(DocsState s) => [
      docsScreenStatusProvider.overrideWith((ref) async {
        switch (s) {
          case DocsState.loading:
            await Completer<void>().future;
            return DocsScreenStatus(const DocsVerification(), null);
          case DocsState.error:
            throw Exception('SocketException: Failed host lookup');
          case DocsState.ok:
            return DocsScreenStatus(DocsVerification(idVerifiedAt: day(-30), licenseVerifiedAt: day(-30)), _gateOk);
          case DocsState.missing:
            return DocsScreenStatus(DocsVerification(idVerifiedAt: day(-30)), kGateMissing);
          case DocsState.idOnly:
            return DocsScreenStatus(DocsVerification(idVerifiedAt: day(-30)), null);
          case DocsState.none:
            return DocsScreenStatus(const DocsVerification(), null);
        }
      }),
    ];

const _gateOk = DocsGateChecklist(
  ok: true, idFront: true, idBack: true, passport: false, dlFront: true, dlBack: true,
  identityOk: true, licenseOk: true, hasDob: true, ageOk: true, expiryOk: true, groupsOk: true,
);

/// The 20 levels as today's DB seeds them (each level's OWN old seed colour
/// → the ramp maps them; one grey for all hid look-alike VIP badges).
List<LoyaltyLevel> levels() => [
      for (var l = 1; l <= 20; l++)
        LoyaltyLevel(level: l, percent: l, minBookingOrder: l, name: loyaltyDefaultRankNamesCs[l]!, colorHex: kRankOldSeedHex[l - 1]),
    ];

List<Override> loyaltyOverrides({LoyaltyStatus? status, bool loading = false, bool error = false}) => [
      loyaltyStatusProvider.overrideWith((ref) async => status),
      loyaltyLevelsProvider.overrideWith((ref) async {
        if (loading) await Completer<void>().future;
        if (error) throw Exception('timeout');
        return levels();
      }),
      loyaltyLeaderboardEnabledProvider.overrideWith((ref) async => false),
    ];

List<Override> branchesOverrides() => [
      branchesInfoProvider.overrideWith((ref, lang) async => branchesInfoDefaults),
      motorcyclesProvider.overrideWith((ref) => Stream.value(kMotos)),
    ];

/// A valid 1×1 PNG (chat photo thumbnails).
final Uint8List kPng1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0xF8, 0xCF, 0x50,
  0x0F, 0x00, 0x03, 0x86, 0x01, 0x80, 0x5A, 0x34, 0x7D, 0x6B, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
