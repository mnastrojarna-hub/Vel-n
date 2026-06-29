import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../theme.dart';
import '../services/api.dart';
import '../services/command_listener.dart';
import '../services/hardware.dart';
import '../services/kiosk_storage.dart';
import '../services/power_poller.dart';
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
    PowerPoller.instance.stop();
    super.dispose();
  }

  Future<void> _heartbeat() async {
    final res = await KioskApi.instance.heartbeat(platform: 'android');
    if (mounted) setState(() => _online = res != null);
    // Nastav stahování stavu FV elektrárny dle konfigurace pobočky.
    if (res != null) {
      PowerPoller.instance.configure(
        res['power_status_url'] as String?,
        (res['power_poll_seconds'] as int?) ?? 60,
      );
    }
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
      _showServicePanel(res);
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
      final next = kind == 'accessories'
          ? '$name\n\nPo vyzvednutí oblečení zavřete dveře a zadejte kód k motorce.'
          : kind == 'motorcycle'
              ? '$name\n\nPříjemnou cestu! 🏍️'
              : name;
      _showOverlay(StatusOverlay(
        kind: StatusKind.success,
        title: 'Otevřeno',
        subtitle: next,
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

  // ── Servisní režim — panel (dveře + hudba + nastavení) ──────────────────────
  // Zobrazí se VÝHRADNĚ po zadání servisního hesla. Pro běžného uživatele je
  // appka strohá (jen zadání kódu); zákaznický kód otevírá vše automaticky.
  void _showServicePanel(ResolveResult res) {
    _showOverlay(_ServicePanel(
      res: res,
      online: _online,
      onPick: (door) async {
        await _openDoor(
          door: door,
          kind: 'service',
          musicUrl: res.musicOnUrl,
          boxNumber: door.boxNumber,
          doorConfigured: (door.relayUrl ?? '').isNotEmpty,
        );
      },
      onMusicOn: () => Hardware.instance.startMusic(res.musicOnUrl),
      onMusicOff: () => Hardware.instance.stopMusic(res.musicOffUrl),
      onRepair: _openSetup,
      onClose: _hideOverlay,
    ));
  }

  Future<void> _openSetup() async {
    _hideOverlay();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SetupScreen(onDone: () => Navigator.of(context).pop()),
    ));
    // Po případném přepárování restartuj realtime + heartbeat
    CommandListener.instance.start();
    _heartbeat();
    if (mounted) setState(() {});
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
                    // Hlavička — strohá (logo + název pobočky)
                    Row(
                      children: [
                        Image.asset('assets/logo.png', height: 48),
                        const Spacer(),
                        Text(branchName,
                            style: TextStyle(
                                color: MG.white.withValues(alpha: 0.85),
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Výzva + stručný postup pro zákazníka
                    Text('Zadejte přístupový kód',
                        style: TextStyle(color: MG.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Kód najdete v potvrzení rezervace — e‑mail nebo aplikace MotoGo24.\n'
                      '1) Kód k oblečení otevře skříň  ·  2) po zavření kód k motorce otevře vaši garáž.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: MG.white.withValues(alpha: 0.6), fontSize: 14, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 78,
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 720),
                      alignment: Alignment.center,
                      decoration: MG.glass(radius: 18),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Klávesnice — vyplní zbylou výšku (responzivní, bez overflow)
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: KioskKeyboards(
                            enabled: !_busy,
                            onChar: _onChar,
                            onBackspace: _onBackspace,
                            onEnter: _submit,
                            onClear: _onClear,
                          ),
                        ),
                      ),
                    ),
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

// ── Servisní panel (dveře + hudba + nastavení) — jen po servisním hesle ───────
class _ServicePanel extends StatelessWidget {
  final ResolveResult res;
  final bool online;
  final Future<void> Function(DoorInfo door) onPick;
  final VoidCallback onMusicOn;
  final VoidCallback onMusicOff;
  final VoidCallback onRepair;
  final VoidCallback onClose;
  const _ServicePanel({
    required this.res,
    required this.online,
    required this.onPick,
    required this.onMusicOn,
    required this.onMusicOff,
    required this.onRepair,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final store = KioskStorage.instance;
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: Container(
        width: 920,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.all(32),
        decoration: MG.glass(radius: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.build_rounded, color: MG.amber, size: 30),
                const SizedBox(width: 12),
                Text('Servisní režim — ${res.kind == 'service' ? (store.branchName ?? 'pobočka') : ''}',
                    style: const TextStyle(color: MG.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded, color: MG.white, size: 30)),
              ],
            ),
            const SizedBox(height: 8),
            _label('Otevřít dveře'),
            if (res.doors.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
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
                  children: [for (final d in res.doors) _DoorTile(door: d, onTap: () => onPick(d))],
                ),
              ),
            const SizedBox(height: 16),
            _label('Hudba'),
            Row(
              children: [
                _panelBtn(Icons.play_arrow_rounded, 'Spustit hudbu', MG.green, MG.black, onMusicOn),
                const SizedBox(width: 12),
                _panelBtn(Icons.stop_rounded, 'Zastavit hudbu', MG.white.withValues(alpha: 0.1), MG.white, onMusicOff),
              ],
            ),
            const SizedBox(height: 20),
            _label('Nastavení zařízení'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: MG.glass(radius: 14),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? MG.green : MG.red)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${online ? 'Online' : 'Offline'} · pobočka: ${store.branchName ?? '—'}\nID: ${store.deviceId ?? '—'}',
                      style: TextStyle(color: MG.white.withValues(alpha: 0.8), fontSize: 14),
                    ),
                  ),
                  _panelBtn(Icons.link_rounded, 'Přepárovat', MG.white.withValues(alpha: 0.1), MG.white, onRepair),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(t.toUpperCase(),
              style: TextStyle(color: MG.white.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      );

  Widget _panelBtn(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
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
