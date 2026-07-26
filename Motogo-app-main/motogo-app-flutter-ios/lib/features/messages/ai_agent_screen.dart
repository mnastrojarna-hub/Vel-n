import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
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
  // Fotky budíků/kontrolek přiložené k příští zprávě (JPEG bytes, max 3) —
  // AI je porovná s návodem motorky (backend ai-moto-agent už images umí).
  final _pendingImages = <Uint8List>[];

  bool _greeted = false;

  @override
  void initState() {
    super.initState();
    _fetchActiveBooking();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Greeting added here (not initState) so Localizations is available.
    if (!_greeted) {
      _greeted = true;
      _messages.add(_ChatMsg(text: t(context).tr('aiGreeting'), isBot: true));
    }
  }

  Future<void> _fetchActiveBooking() async {
    try {
      final user = MotoGoSupabase.currentUser;
      if (user == null) return;
      // Servisní chat se má vztahovat k motorce, na které zákazník PRÁVĚ jede.
      // Dřívější `limit(1)` řazený dle start_date vracel budoucí rezervaci místo
      // běžícího pronájmu (novější start_date vyhrál) → agent radil k jiné motorce.
      final rows = await MotoGoSupabase.client.from('bookings')
          .select('id, status')
          .eq('user_id', user.id)
          .inFilter('status', ['active', 'reserved'])
          .eq('payment_status', 'paid')
          .order('start_date', ascending: false)
          .limit(10) as List;
      if (rows.isEmpty) return;
      final active = rows.cast<Map<String, dynamic>>()
          .where((r) => r['status'] == 'active').toList();
      _bookingId = (active.isNotEmpty ? active.first : rows.first)['id'] as String;
    } catch (_) {}
  }

  Future<void> _send() async {
    var text = _inputCtrl.text.trim();
    final images = List<Uint8List>.from(_pendingImages);
    if ((text.isEmpty && images.isEmpty) || _sending) return;
    // Samotná fotka bez textu: backend vyžaduje neprázdnou zprávu.
    if (text.isEmpty) text = t(context).tr('aiPhotoOnlyMsg');

    final lang = Localizations.localeOf(context).languageCode;

    setState(() {
      _messages.add(_ChatMsg(text: text, isBot: false, images: images));
      _pendingImages.clear();
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    // Build conversation history (without greeting / SOS hint chips) so the
    // agent has context of the whole chat — without this every message was
    // answered in isolation.
    final history = <Map<String, String>>[];
    for (final m in _messages) {
      if (m.isSosHint) continue;
      if (m.isBot && m == _messages.first) continue; // skip greeting
      history.add({'role': m.isBot ? 'assistant' : 'user', 'content': m.text});
    }
    // Drop the just-added user message — it's sent separately as `message`.
    if (history.isNotEmpty && history.last['role'] == 'user') history.removeLast();

    try {
      final res = await MotoGoSupabase.client.functions.invoke(
        'ai-moto-agent',
        body: {
          'message': text,
          'booking_id': _bookingId,
          'lang': lang,
          'conversation_history': history,
          'supports_images': true,
          if (images.isNotEmpty)
            'images': [
              for (final img in images)
                {'base64': base64Encode(img), 'media_type': 'image/jpeg'},
            ],
        },
      );

      final data = res.data as Map<String, dynamic>?;
      final replyData = data?['reply'] as String?;
      final suggestSos = data?['suggest_sos'] as bool? ?? false;

      if (mounted) {
        final reply = replyData ?? t(context).tr('aiProcessError');
        setState(() {
          _messages.add(_ChatMsg(text: reply, isBot: true));
          if (suggestSos) {
            _messages.add(_ChatMsg(
              text: t(context).tr('aiSuggestSos'),
              isBot: true,
              isSosHint: true,
            ));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(_ChatMsg(
          text: t(context).tr('aiCommError'),
          isBot: true,
        )));
      }
    }

    if (mounted) {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _attachPhoto() async {
    if (_pendingImages.length >= 3) {
      showMotoGoToast(context, icon: '📷', title: t(context).tr('aiPhotoLimit'));
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(t(ctx).tr('aiTakePhoto')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(t(ctx).tr('aiPickGallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      // Komprese jako v SOS reportu; 1280 px bohatě stačí na čitelnost kontrolek
      // a 3 fotky se vejdou do request limitu edge funkce.
      final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 75, maxWidth: 1280,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingImages.add(bytes));
    } catch (_) {
      if (mounted) showMotoGoToast(context, icon: '⚠️', title: t(context).tr('aiPhotoError'));
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
          onTap: () => context.backOr(Routes.home),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Text('🤖 ${t(context).tr('aiServiceAgent')}'),
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
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(t(context).tr('aiThinking'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                    ),
                  );
                }
                final msg = _messages[i];
                return _buildBubble(msg);
              },
            ),
          ),

          // Náhledy přiložených fotek
          if (_pendingImages.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                for (var i = 0; i < _pendingImages.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_pendingImages[i],
                            width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 0, right: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _pendingImages.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: MotoGoColors.g200)),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: _attachPhoto,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.photo_camera_outlined,
                      size: 26,
                      color: _pendingImages.isEmpty ? MotoGoColors.g400 : MotoGoColors.green),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: InputDecoration(
                    hintText: t(context).tr('aiDescribeProblemHint'),
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
            child: Row(children: [
              const Text('🆘', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t(context).tr('reportSosIncident'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C))),
                Text(t(context).tr('clickToReportProblem'), style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B))),
              ])),
              const Text('›', style: TextStyle(fontSize: 16, color: Color(0xFFB91C1C))),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final img in msg.images)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(img, width: 120, fit: BoxFit.cover),
                  ),
              ]),
            ),
          Text(msg.text, style: const TextStyle(fontSize: 13, color: MotoGoColors.black, height: 1.5)),
        ]),
      ),
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isBot;
  final bool isSosHint;
  final List<Uint8List> images;
  _ChatMsg({required this.text, required this.isBot, this.isSosHint = false, this.images = const []});
}
