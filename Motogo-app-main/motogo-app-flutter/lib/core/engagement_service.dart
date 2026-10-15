import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'i18n/i18n_provider.dart' show lastKnownAppLang;
import 'supabase_client.dart';

/// Měření pro Velín → Analýza → App funnel (tabulka `web_engagement`,
/// `source = 'app'`) — obdoba webového `js/engage.js`.
///
/// * `visit` = člověk měl appku v POPŘEDÍ aspoň 5 s A dotkl se displeje
///   (skutečný dotyk z `Listener` v `MaterialApp.builder`, main.dart).
/// * `calc`  = rezervační formulář spočítal cenu (motorka + termín) po dotyku
///   člověka — appka nemá samostatnou kalkulačku, cenu ukazuje formulář.
///
/// Debug buildy se nepočítají. Anonymní: místo identifikátoru zařízení se
/// posílá NÁHODNÝ denní token (32 B hex, nový každý den, nikam nenavázaný) —
/// 1 člověk = nejvýš 1 návštěva / 1 kalkulace za den (lokálně i unikátním
/// indexem v DB). Nikdy nevyhazuje výjimku ani neblokuje UI.
class EngagementService {
  EngagementService._();

  static const _needForeground = Duration(seconds: 5);
  static const _tokenKey = 'mg_engage_token';
  static const _sentKey = 'mg_engage_sent';

  static bool _human = false;
  static DateTime? _fgSince;
  static Duration _fg = Duration.zero;
  static Timer? _timer;
  static final Map<String, String> _doneDay = {}; // událost → den, kdy je zapsaná
  static final Set<String> _sending = {};

  static bool get _enabled => !kDebugMode;

  /// Start při spuštění appky (initState v main.dart) — appka je v popředí.
  static void start() {
    if (_enabled) _fgSince ??= DateTime.now();
  }

  /// Skutečný dotyk člověka (volá `Listener.onPointerDown` v main.dart).
  static void onUserPointer() {
    if (!_enabled || _human) return;
    _human = true;
    _check();
  }

  /// Popředí/pozadí appky (volá `didChangeAppLifecycleState` v main.dart).
  static void onLifecycle(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.resumed) {
      _fgSince ??= DateTime.now();
      _check();
    } else if (_fgSince != null) {
      _fg += DateTime.now().difference(_fgSince!);
      _fgSince = null;
    }
  }

  /// Rezervační formulář ukázal cenu — počítá se jen po dotyku člověka.
  static void trackCalc() {
    if (_enabled && _human && _doneDay['calc'] != _today()) _send('calc');
  }

  /// Hlídá 5 s v popředí. Znovu se nastaví při každém návratu do appky,
  /// takže dožene i výpadek sítě a nový den při dlouho otevřené appce.
  static void _check() {
    if (!_human || _timer != null || _doneDay['visit'] == _today()) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final total =
          _fg + (_fgSince == null ? Duration.zero : DateTime.now().difference(_fgSince!));
      if (total >= _needForeground) {
        t.cancel();
        _timer = null;
        _send('visit');
      }
    });
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _randomHex() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<void> _send(String event) async {
    if (!_sending.add(event)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final day = _today();
      final sent = prefs.getStringList(_sentKey) ?? const <String>[];
      if (sent.contains('$day|$event')) {
        _doneDay[event] = day;
        return;
      }

      // Denní anonymní token (nový každý den).
      var token = prefs.getString(_tokenKey) ?? '';
      if (!token.startsWith('$day|')) {
        token = '$day|${_randomHex()}';
        await prefs.setString(_tokenKey, token);
      }

      try {
        await MotoGoSupabase.client.from('web_engagement').insert({
          'source': 'app',
          'event': event,
          'visitor_hash': token.substring(day.length + 1),
          'device': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'lang': lastKnownAppLang,
        });
      } on PostgrestException catch (e) {
        // 23505 = dnes už zapsáno (unikátní index) → hotovo; jiná chyba → příště.
        if (e.code != '23505') return;
      } catch (_) {
        return; // offline apod. → zkusí se při dalším návratu do appky
      }
      _doneDay[event] = day;
      await prefs.setStringList(_sentKey, [
        ...sent.where((s) => s.startsWith('$day|')),
        '$day|$event',
      ]);
    } catch (_) {
      // analytika nesmí shodit appku
    } finally {
      _sending.remove(event);
    }
  }
}
