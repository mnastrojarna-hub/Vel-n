// v2 Profil sub-screens (PLAN §5.3, area "profile"): Zprávy, vlákno, AI
// asistent, Moje doklady, Faktury, Dokumenty a smlouvy — through the REAL
// screens' seams where the screen needs no plugin / live client in
// initState, otherwise the v2 view with the data the seam passes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/documents/contracts_screen.dart';
import 'package:motogo_app/features/documents/documents_screen.dart';
import 'package:motogo_app/features/documents/invoices_screen.dart';
import 'package:motogo_app/features/messages/ai_agent_screen.dart';
import 'package:motogo_app/features/messages/messages_screen.dart';
import 'package:motogo_app/features/messages/v2/ai_chat_parts_v2.dart';
import 'package:motogo_app/features/messages/v2/ai_chat_view_v2.dart';
import 'package:motogo_app/features/messages/v2/messages_parts_v2.dart';
import 'package:motogo_app/features/messages/v2/thread_view_v2.dart';
import 'package:motogo_app/core/widgets/state_views.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_profile.dart' show registerProfileStrings;
import '../support/fakes_profile_sub.dart';
import '../support/profile_matrix.dart';
import '../support/v2_harness.dart';

Future<void> _toThreads(WidgetTester t) async {
  final seg = find.byType(MsgSegmentsV2);
  if (seg.evaluate().isEmpty) return;
  final r = t.getRect(seg);
  await t.tapAt(Offset(r.right - 24, r.center.dy));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _expandNote(WidgetTester t) async => pfTap(t, find.byType(MsgNoteCardV2).at(1));

Widget _thread({bool closed = false, bool empty = false, Widget? state}) {
  final th = threads()[closed ? 1 : 0];
  return ThreadViewV2(
    thread: state != null ? null : (empty ? (threads()..first.messages.clear()).first : th),
    state: state,
    sending: false,
    replyCtrl: TextEditingController(text: closed ? '' : 'Díky, čekám u motorky.'),
    scrollCtrl: ScrollController(),
    onBack: () {},
    onSend: () {},
  );
}

Widget _ai({bool sending = false, bool slow = false, bool photos = false}) => AiChatViewV2(
      items: [
        const AiChatItemV2(text: '👋 Ahoj! Jsem MotoGo AI asistent. S čím ti můžu pomoct?', isBot: true),
        AiChatItemV2(text: 'Svítí mi oranžová kontrolka motoru, co s tím?', isBot: false, images: [kPng1], failed: true, onRetry: () {}),
        const AiChatItemV2(text: '❌ Asistent teď neodpovídá. Zkus to prosím za chvilku znovu.', isBot: true, isError: true),
        const AiChatItemV2(text: 'Nahlásit SOS', isBot: true, isSosHint: true),
        const AiChatItemV2(text: 'Oranžová kontrolka motoru znamená závadu snímače. Můžeš opatrně pokračovat, sniž rychlost a sleduj teplotu.', isBot: true),
      ],
      sending: sending,
      slow: slow,
      pendingImages: photos ? [kPng1, kPng1] : const [],
      onRemoveImage: (_) {},
      inputCtrl: TextEditingController(),
      scrollCtrl: ScrollController(),
      onBack: () {},
      onSend: () {},
      onAttach: () {},
      onSos: () {},
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerProfileStrings();
    mockPathProvider();
  });

  pfMatrix([
    PfCase('messages', 'notes', () => const MessagesScreen(), () => messagesOverrides()),
    PfCase('messages', 'note_open', () => const MessagesScreen(), () => messagesOverrides(), after: _expandNote),
    PfCase('messages', 'push_focus', () => const MessagesScreen(focusId: 'm2'), () => messagesOverrides()),
    PfCase('messages', 'notes_empty', () => const MessagesScreen(), () => messagesOverrides(notesEmpty: true, unread: 0)),
    PfCase('messages', 'notes_loading', () => const MessagesScreen(), () => messagesOverrides(notesLoading: true), settle: false),
    PfCase('messages', 'notes_error', () => const MessagesScreen(), () => messagesOverrides(notesError: true)),
    PfCase('messages', 'threads', () => const MessagesScreen(), () => messagesOverrides(), after: _toThreads, level: 17),
    PfCase('messages', 'threads_empty', () => const MessagesScreen(), () => messagesOverrides(threadsEmpty: true), after: _toThreads),
    PfCase('messages', 'threads_error', () => const MessagesScreen(), () => messagesOverrides(threadsError: true), after: _toThreads),
    PfCase('thread', 'open', () => _thread(), () => const []),
    PfCase('thread', 'closed', () => _thread(closed: true), () => const []),
    PfCase('thread', 'empty', () => _thread(empty: true), () => const []),
    PfCase('thread', 'loading', () => _thread(state: MgLoadingView(onRetry: () {}, onBack: () {})), () => const [], settle: false),
    PfCase('thread', 'error', () => _thread(state: MgErrorView(error: Exception('timeout'), what: 'x', onRetry: () {}, onBack: () {})), () => const []),
    PfCase('ai', 'greeting', () => const AiAgentScreen(), () => const []),
    PfCase('ai', 'chat', () => _ai(), () => const []),
    PfCase('ai', 'typing_photos', () => _ai(sending: true, slow: true, photos: true), () => const [], level: 20, settle: false),
    PfCase('docs', 'verified', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.ok)),
    PfCase('docs', 'missing_dl_back', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.missing), level: 6),
    PfCase('docs', 'id_only', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.idOnly)),
    PfCase('docs', 'nothing', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.none), level: 1),
    PfCase('docs', 'loading', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.loading), settle: false),
    PfCase('docs', 'error', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.error)),
    PfCase('invoices', 'list', () => const InvoicesScreen(), () => docListOverrides()),
    PfCase('invoices', 'empty', () => const InvoicesScreen(), () => docListOverrides(empty: true)),
    PfCase('invoices', 'loading', () => const InvoicesScreen(), () => docListOverrides(loading: true), settle: false),
    PfCase('invoices', 'error', () => const InvoicesScreen(), () => docListOverrides(error: true)),
    PfCase('contracts', 'list', () => const ContractsScreen(), () => docListOverrides()),
    PfCase('contracts', 'empty', () => const ContractsScreen(), () => docListOverrides(empty: true)),
    PfCase('contracts', 'loading', () => const ContractsScreen(), () => docListOverrides(loading: true), settle: false),
    PfCase('contracts', 'error', () => const ContractsScreen(), () => docListOverrides(error: true)),
  ]);

  group('flag off keeps the old screens', () {
    for (final (name, build, ov) in [
      ('messages', () => const MessagesScreen() as Widget, messagesOverrides()),
      ('docs', () => const DocumentsScreen() as Widget, docsStatusOverrides(DocsState.ok)),
      ('invoices', () => const InvoicesScreen() as Widget, docListOverrides()),
      ('contracts', () => const ContractsScreen() as Widget, docListOverrides()),
    ]) {
      testWidgets(name, (tester) async {
        await pumpV2(tester, build(), overrides: ov, v2: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
