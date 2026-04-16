import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';

/// AI Moto Agent chat — mirrors s-ai-agent from ai-agent-ui.js + ai-agent-send.js.
/// Calls ai-moto-agent edge function with booking context.
class AiAgentScreen extends StatefulWidget {
  const AiAgentScreen({super.key});

  @override
  State<AiAgentScreen> createState() => _AiAgentState();
}

class _AiAgentState extends State<AiAgentScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMsg>[];
  bool _sending = false;
  String? _bookingId;

  @override
  void initState() {
    super.initState();
    _fetchActiveBooking();
    _messages.add(_ChatMsg(
      text: '👋 Dobrý den! Jsem MotoGo AI asistent. Jak vám mohu pomoci? '
          'Mohu poradit s kontrolkami, poruchami, manuály nebo technickými dotazy.',
      isBot: true,
    ));
  }

  Future<void> _fetchActiveBooking() async {
    try {
      final user = MotoGoSupabase.currentUser;
      if (user == null) return;
      final res = await MotoGoSupabase.client.from('bookings')
          .select('id')
          .eq('user_id', user.id)
          .inFilter('status', ['active', 'reserved'])
          .eq('payment_status', 'paid')
          .order('start_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res != null) _bookingId = res['id'] as String;
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMsg(text: text, isBot: false));
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      final res = await MotoGoSupabase.client.functions.invoke(
        'ai-moto-agent',
        body: {
          'message': text,
          'booking_id': _bookingId,
        },
      );

      final data = res.data as Map<String, dynamic>?;
      final reply = data?['reply'] as String? ?? 'Omlouvám se, nepodařilo se zpracovat dotaz.';
      final isRideable = data?['is_rideable'] as bool?;
      final suggestSos = data?['suggest_sos'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _messages.add(_ChatMsg(text: reply, isBot: true));
          if (suggestSos) {
            _messages.add(_ChatMsg(
              text: '🆘 Agent doporučuje nahlásit SOS incident.',
              isBot: true,
              isSosHint: true,
            ));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(_ChatMsg(
          text: '❌ Chyba komunikace s AI agentem. Zkuste to znovu.',
          isBot: true,
        )));
      }
    }

    if (mounted) {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: const Text('🤖 AI Servisní agent'),
        backgroundColor: MotoGoColors.dark,
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) {
                  // Typing indicator
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('⏳ Přemýšlím...', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                    ),
                  );
                }
                final msg = _messages[i];
                return _buildBubble(msg);
              },
            ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: MotoGoColors.g200)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: InputDecoration(
                    hintText: 'Popište problém nebo dotaz...',
                    hintStyle: const TextStyle(fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: const BorderSide(color: MotoGoColors.g200)),
                  ),
                  onSubmitted: (_) => _send(),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
                  child: const Icon(Icons.send, size: 20, color: Colors.black),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMsg msg) {
    if (msg.isSosHint) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => context.push(Routes.sos),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MotoGoColors.redBg,
              borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Row(children: [
              Text('🆘', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nahlásit SOS incident', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C))),
                Text('Klikněte pro nahlášení problému', style: TextStyle(fontSize: 11, color: Color(0xFF991B1B))),
              ])),
              Text('›', style: TextStyle(fontSize: 16, color: Color(0xFFB91C1C))),
            ]),
          ),
        ),
      );
    }

    return Align(
      alignment: msg.isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: msg.isBot ? Colors.white : MotoGoColors.green,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isBot ? 4 : 16),
            bottomRight: Radius.circular(msg.isBot ? 16 : 4),
          ),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        child: Text(msg.text, style: const TextStyle(fontSize: 13, color: MotoGoColors.black, height: 1.5)),
      ),
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isBot;
  final bool isSosHint;
  _ChatMsg({required this.text, required this.isBot, this.isSosHint = false});
}
