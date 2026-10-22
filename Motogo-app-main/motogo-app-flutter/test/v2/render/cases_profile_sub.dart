// verify:render cases — Profil sub-screens (profile_sub_test.dart): Zprávy
// (notes / threads + empty / loading / error / push focus), vlákno, AI
// asistent, Moje doklady, Faktury, Dokumenty a smlouvy.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/widgets/state_views.dart';
import 'package:motogo_app/features/documents/contracts_screen.dart';
import 'package:motogo_app/features/documents/documents_screen.dart';
import 'package:motogo_app/features/documents/invoices_screen.dart';
import 'package:motogo_app/features/messages/ai_agent_screen.dart';
import 'package:motogo_app/features/messages/messages_screen.dart';
import 'package:motogo_app/features/messages/v2/ai_chat_parts_v2.dart';
import 'package:motogo_app/features/messages/v2/ai_chat_view_v2.dart';
import 'package:motogo_app/features/messages/v2/messages_parts_v2.dart';
import 'package:motogo_app/features/messages/v2/thread_view_v2.dart';

import '../support/fakes_profile_sub.dart';
import '../support/profile_matrix.dart' show pfTap;
import 'render_harness.dart';

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
        const AiChatItemV2(
            text: 'Oranžová kontrolka motoru znamená závadu snímače. Můžeš opatrně pokračovat, sniž rychlost a sleduj teplotu.', isBot: true),
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

RenderCase _p(String screen, String state, Widget Function() b, List<Override> Function() o,
        {int level = 3, Future<void> Function(WidgetTester)? after, bool loading = false}) =>
    RenderCase('profile', screen, state, b, o, level: level, after: after, loading: loading);

List<RenderCase> profileSubRenderCases() => [
      _p('messages', 'notes', () => const MessagesScreen(), () => messagesOverrides()),
      _p('messages', 'note_open', () => const MessagesScreen(), () => messagesOverrides(), after: _expandNote),
      _p('messages', 'push_focus', () => const MessagesScreen(focusId: 'm2'), () => messagesOverrides()),
      _p('messages', 'notes_empty', () => const MessagesScreen(), () => messagesOverrides(notesEmpty: true, unread: 0)),
      _p('messages', 'notes_loading', () => const MessagesScreen(), () => messagesOverrides(notesLoading: true), loading: true),
      _p('messages', 'notes_error', () => const MessagesScreen(), () => messagesOverrides(notesError: true)),
      _p('messages', 'threads', () => const MessagesScreen(), () => messagesOverrides(), after: _toThreads, level: 17),
      _p('messages', 'threads_empty', () => const MessagesScreen(), () => messagesOverrides(threadsEmpty: true), after: _toThreads),
      _p('messages', 'threads_error', () => const MessagesScreen(), () => messagesOverrides(threadsError: true), after: _toThreads),
      _p('thread', 'open', () => _thread(), () => const []),
      _p('thread', 'closed', () => _thread(closed: true), () => const []),
      _p('thread', 'empty', () => _thread(empty: true), () => const []),
      _p('thread', 'loading', () => _thread(state: MgLoadingView(onRetry: () {}, onBack: () {})), () => const [], loading: true),
      _p('thread', 'error', () => _thread(state: MgErrorView(error: Exception('timeout'), what: 'x', onRetry: () {}, onBack: () {})),
          () => const []),
      _p('ai', 'greeting', () => const AiAgentScreen(), () => const []),
      _p('ai', 'chat', () => _ai(), () => const []),
      _p('ai', 'typing_photos', () => _ai(sending: true, slow: true, photos: true), () => const [], level: 20, loading: true),
      _p('docs', 'verified', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.ok)),
      _p('docs', 'missing_dl_back', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.missing), level: 6),
      _p('docs', 'id_only', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.idOnly)),
      _p('docs', 'nothing', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.none), level: 1),
      _p('docs', 'loading', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.loading), loading: true),
      _p('docs', 'error', () => const DocumentsScreen(), () => docsStatusOverrides(DocsState.error)),
      _p('invoices', 'list', () => const InvoicesScreen(), () => docListOverrides()),
      _p('invoices', 'empty', () => const InvoicesScreen(), () => docListOverrides(empty: true)),
      _p('invoices', 'loading', () => const InvoicesScreen(), () => docListOverrides(loading: true), loading: true),
      _p('invoices', 'error', () => const InvoicesScreen(), () => docListOverrides(error: true)),
      _p('contracts', 'list', () => const ContractsScreen(), () => docListOverrides()),
      _p('contracts', 'empty', () => const ContractsScreen(), () => docListOverrides(empty: true)),
      _p('contracts', 'loading', () => const ContractsScreen(), () => docListOverrides(loading: true), loading: true),
      _p('contracts', 'error', () => const ContractsScreen(), () => docListOverrides(error: true)),
    ];
