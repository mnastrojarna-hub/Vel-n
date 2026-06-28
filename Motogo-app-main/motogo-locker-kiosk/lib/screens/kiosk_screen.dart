import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../theme.dart';
import '../services/api.dart';
import '../services/command_listener.dart';
import '../services/hardware.dart';
import '../services/kiosk_storage.dart';
import '../widgets/keyboards.dart';
import '../widgets/status_overlay.dart';
import 'setup_screen.dart';

class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  String _entry = '';
  bool _busy = false;
  Widget? _overlay; // status / service picker
  Timer? _hideTimer;
  Timer? _hbTimer;
  bool _online = false;

  static const int _maxLen = 24;

  @override
  void initState() {
    super.initState();
    CommandListener.instance
      ..onIdentify = _onIdentify
      ..onReload = _onReload
      ..start();
    _heartbeat();
    _hbTimer = Timer.periodic(KioskConfig.heartbeatInterval, (_) => _heartbeat());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hbTimer?.cancel();
    CommandListener.instance.stop();
    super.dispose();
  }

  Future<void> _heartbeat() async {
    final res = await KioskApi.instance.heartbeat(platform: 'android');
    if (mounted) setState(() => _online = res != null);
    // Pojistka: stáhni i vzdálené příkazy, kdyby broadcast nedorazil.
    CommandListener.instance.drain();
  }

  void _onIdentify(String label) {
    if (!mounted) return;
    _showOverlay(StatusOverlay(
      kind: StatusKind.success,
      title: 'Tady jsem 👋',
      subtitle: 'Identifikace z Velína ($label)',
      onDismiss: _hideOverlay,
    ));
    _autoHide();
  }

  void _onReload() {
    if (!mounted) return;
    setState(() => _entry = '');
    _hideOverlay();
    _heartbeat();
  }

  // ── Zadávání ──────────────────────────────────────────────────────────────
  void _onChar(String ch) {
    if (_busy || _entry.length >= _maxLen) return;
    setState(() => _entry += ch);
  }

  void _onBackspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _onClear() {
    if (_busy) return;
    setState(() => _entry = '');
  }

  void _showOverlay(Widget w) => setState(() => _overlay = w);
  void _hideOverlay() => setState(() => _overlay = null);

  void _autoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(KioskConfig.statusAutoHide, () {
      if (mounted) _hideOverlay();
    });
  }

  // ── Potvrzení kódu ──────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final code = _entry.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    _showOverlay(const StatusOverlay(kind: StatusKind.working, title: 'Ověřuji kód…'));

    final res = await KioskApi.instance.resolveCode(code);
    setState(() => _entry = '');

    if (!res.ok) {
      _busy = false;
      _showOverlay(StatusOverlay(
        kind: StatusKind.error,
        title: 'Neplatný kód',
        subtitle: _errorText(res.error),
        onDismiss: _hideOverlay,
      ));
      _autoHide();
      return;
    }

    if (res.isService) {
      _busy = false;
      _showServicePicker(res);
      return;
    }

    // Zákaznický kód — otevři konkrétní dveře
    await _openDoor(
      door: res.door,
      kind: res.kind,
      bookingId: res.bookingId,
      boxNumber: res.boxNumber,
      musicUrl: res.musicOnUrl,
      doorConfigured: res.doorConfigured,
    );
    _busy = false;
  }

  // ── Otevření dveří + světlo + hudba ─────────────────────────────────────────
  Future<void> _openDoor({
    required DoorInfo? door,
    required String kind,
    String? bookingId,
    int? boxNumber,
    String? musicUrl,
    bool doorConfigured = true,
  }) async {
    final name = door?.displayName ??
        (kind == 'accessories' ? 'Oblečení' : (boxNumber != null ? 'Garáž #$boxNumber' : 'Dveře'));

    if (door == null || !doorConfigured || (door.relayUrl ?? '').isEmpty) {
      // Kód platí, ale dveře nemají nastavené relé ve Velíně
      await KioskApi.instance.logOpen(
        doorId: door?.id, kind: kind, bookingId: bookingId, success: false,
        detail: {'reason': 'door_not_configured', 'box_number': boxNumber},
      );
      _showOverlay(StatusOverlay(
        kind: StatusKind.error,
        title: 'Dveře nejsou nastaveny',
        subtitle: 'Kód je platný ($name), ale relé pro tyto dveře není ve Velíně\nnastaveno. Kontaktujte podporu: +420 774 256 271.',
        onDismiss: _hideOverlay,
      ));
      _autoHide();
      return;
    }

    _showOverlay(StatusOverlay(kind: StatusKind.working, title: 'Otevírám $name…'));

    // Hudba na celé pobočce + světlo v garáži + zámek
    if ((musicUrl ?? '').isNotEmpty) Hardware.instance.startMusic(musicUrl);
    Hardware.instance.turnOnLight(door.lightUrl);
    final opened = await Hardware.instance.openDoor(door.relayUrl);

    await KioskApi.instance.logOpen(
      doorId: door.id, kind: kind, bookingId: bookingId, success: opened,
      detail: {'box_number': door.boxNumber},
    );

    if (opened) {
      _showOverlay(StatusOverlay(
        kind: StatusKind.success,
        title: 'Otevřeno',
        subtitle: name,
        onDismiss: _hideOverlay,
      ));
    } else {
      _showOverlay(StatusOverlay(
        kind: StatusKind.error,
        title: 'Dveře se neozvaly',
        subtitle: 'Zkuste to prosím znovu nebo kontaktujte\npodporu: +420 774 256 271.',
        onDismiss: _hideOverlay,
      ));
    }
    _autoHide();
  }

  // ── Servisní režim — výběr dveří ────────────────────────────────────────────
  void _showServicePicker(ResolveResult res) {
    _showOverlay(_ServicePicker(
      res: res,
      onPick: (door) async {
        await _openDoor(
          door: door,
          kind: 'service',
          musicUrl: res.musicOnUrl,
          boxNumber: door.boxNumber,
          doorConfigured: (door.relayUrl ?? '').isNotEmpty,
        );
      },
      onClose: _hideOverlay,
    ));
  }

  String _errorText(String? error) {
    switch (error) {
      case 'invalid_code':
        return 'Kód nebyl rozpoznán nebo už není platný.';
      case 'network':
        return 'Chyba spojení. Zkontrolujte internet a zkuste znovu.';
      case 'unauthorized':
      case 'branch_not_found':
        return 'Kiosk není správně spárovaný s pobočkou.';
      default:
        return 'Zkuste to prosím znovu.';
    }
  }

  // ── Skrytý vstup do nastavení (5× klepnutí na logo) ─────────────────────────
  int _logoTaps = 0;
  Timer? _logoTimer;
  void _onLogoTap() {
    _logoTaps++;
    _logoTimer?.cancel();
    _logoTimer = Timer(const Duration(seconds: 2), () => _logoTaps = 0);
    if (_logoTaps >= 5) {
      _logoTaps = 0;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SetupScreen(onDone: () => Navigator.of(context).pop()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchName = KioskStorage.instance.branchName ?? 'Samoobslužná pobočka';
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: MG.bgGradient),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
                child: Column(
                  children: [
                    // Hlavička
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _onLogoTap,
                          child: Image.asset('assets/logo.png', height: 48),
                        ),
                        const Spacer(),
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _online ? MG.green : MG.red,
                          ),
                        ),
                        Text(branchName,
                            style: TextStyle(
                                color: MG.white.withValues(alpha: 0.85),
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const Spacer(),
                    // Výzva + display kódu
                    Text('Zadejte přístupový kód',
                        style: TextStyle(color: MG.white.withValues(alpha: 0.7), fontSize: 22)),
                    const SizedBox(height: 16),
                    Container(
                      height: 84,
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 720),
                      alignment: Alignment.center,
                      decoration: MG.glass(radius: 18),
                      child: Text(
                        _entry.isEmpty ? '— — — — — —' : _entry.toUpperCase(),
                        style: TextStyle(
                          color: _entry.isEmpty ? MG.white.withValues(alpha: 0.3) : MG.green,
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Klávesnice
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: KioskKeyboards(
                        enabled: !_busy,
                        onChar: _onChar,
                        onBackspace: _onBackspace,
                        onEnter: _submit,
                        onClear: _onClear,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          if (_overlay != null) Positioned.fill(child: _overlay!),
        ],
      ),
    );
  }
}

// ── Výběr dveří v servisním režimu ────────────────────────────────────────────
class _ServicePicker extends StatelessWidget {
  final ResolveResult res;
  final Future<void> Function(DoorInfo door) onPick;
  final VoidCallback onClose;
  const _ServicePicker({required this.res, required this.onPick, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: Container(
        width: 900,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(32),
        decoration: MG.glass(radius: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.build_rounded, color: MG.amber, size: 30),
                const SizedBox(width: 12),
                const Text('Servisní režim — vyberte dveře',
                    style: TextStyle(color: MG.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: MG.white, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (res.doors.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Pro tuto pobočku nejsou nastavené žádné dveře.',
                    style: TextStyle(color: MG.white.withValues(alpha: 0.7), fontSize: 18)),
              )
            else
              Flexible(
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.3,
                  children: [
                    for (final d in res.doors)
                      _DoorTile(door: d, onTap: () => onPick(d)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoorTile extends StatelessWidget {
  final DoorInfo door;
  final VoidCallback onTap;
  const _DoorTile({required this.door, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAcc = door.kind == 'accessories';
    final configured = (door.relayUrl ?? '').isNotEmpty;
    return Material(
      color: MG.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: configured ? MG.green.withValues(alpha: 0.5) : MG.red.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isAcc ? Icons.checkroom_rounded : Icons.garage_rounded,
                  color: configured ? MG.green : MG.red, size: 34),
              const SizedBox(height: 8),
              Text(door.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MG.white, fontSize: 16, fontWeight: FontWeight.w800)),
              if (!configured)
                Text('bez relé',
                    style: TextStyle(color: MG.red.withValues(alpha: 0.9), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
