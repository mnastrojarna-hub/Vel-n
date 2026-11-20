import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/payment_pending_marker.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart' show authStateProvider;
import 'gear_order_api.dart';
import 'gear_order_state.dart';
import 'gear_quote.dart';

/// Přihlášený zákazník (id + e-mail účtu); testy ho podstrčí. Sleduje
/// přihlášení/odhlášení — jiný účet bez restartu appky = jiný e-mail
/// i klíč konceptu (jinak `email_mismatch`).
final gearOrderUserProvider = Provider.autoDispose<(String?, String)>((ref) {
  try {
    ref.watch(authStateProvider);
  } catch (_) {}
  try {
    final u = MotoGoSupabase.currentUser;
    return (u?.id, (u?.email ?? '').trim().toLowerCase());
  } catch (_) {
    return (null, '');
  }
});

/// Klíč nezaplaceného konceptu výpůjčky výbavy (per účet).
String gearDraftKey(String? userId) => 'gear_draft_${userId ?? 'anon'}';

/// Zaplaceno → koncept se už znovu nepoužije (web `paidView`).
Future<void> gearForgetDraft(String? userId) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(gearDraftKey(userId));
  } catch (_) {}
}

/// Založená rezervace → platba (`payGearBooking`).
class GearCreated {
  final String bookingId;
  final double amount;

  /// Přepsaný nezaplacený koncept (`reused`) — server mu nechá původní
  /// `created_at`, 4h okno na zaplacení tedy běží od vzniku konceptu.
  final bool reused;
  const GearCreated(this.bookingId, this.amount, {this.reused = false});
}

final gearOrderProvider = StateNotifierProvider.autoDispose<GearOrderController, GearOrderState>((ref) {
  final user = ref.watch(gearOrderUserProvider);
  return GearOrderController(ref.watch(gearOrderApiProvider), userId: user.$1, email: user.$2);
});

/// Logika formuláře výbavy 1:1 jako web (`js/gear-rental.js`, `-price.js`,
/// `-submit.js`): termín, pobočka, kusy a velikosti, sklad (200 ms),
/// serverová cena (350 ms), dárkový poukaz, kontrola a založení rezervace.
class GearOrderController extends StateNotifier<GearOrderState> {
  GearOrderController(this.api, {this.userId, this.email = '', this.availDelay = const Duration(milliseconds: 200), this.quoteDelay = const Duration(milliseconds: 350)})
      : super(GearOrderState()..contact.email = email) {
    _loadDraft();
  }

  final GearOrderApi api;
  final String? userId;
  final String email;
  final Duration availDelay;
  final Duration quoteDelay;
  Timer? _availT, _quoteT;
  int _quoteN = 0;

  String get _draftKey => gearDraftKey(userId);

  void _set(void Function(GearOrderState s) f) {
    if (!mounted) return;
    final s = state.copy();
    f(s);
    // Chyba kontroly formuláře zmizí, jakmile její pole platí (dřív visela
    // v souhrnu i doku až do dalšího odeslání); chyby serveru zůstanou.
    final e = s.error;
    if (e == null) {
      _formErr = false;
    } else if (_formErr && _check(s) != e) {
      s.error = null;
      _formErr = false;
    }
    state = s;
  }

  /// Zobrazená chyba pochází z [validate] (ne z odpovědi serveru).
  bool _formErr = false;

  Future<void> _loadDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = p.getString(_draftKey);
      if (id != null && id.isNotEmpty) _set((s) => s.draftId = id);
    } catch (_) {}
  }

  Future<void> _saveDraft(String? id) async {
    _set((s) => s.draftId = id);
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null) {
        await p.remove(_draftKey);
      } else {
        await p.setString(_draftKey, id);
      }
    } catch (_) {}
  }

  /// Zaplacená rezervace → koncept už nepoužívat (web `paidView`).
  Future<void> clearDraft() => _saveDraft(null);

  static Future<bool> _paymentPending(String id) async {
    try {
      return await PaymentPendingMarker.isPending(id);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _availT?.cancel();
    _quoteT?.cancel();
    super.dispose();
  }

  /// Podklady načtené → jediná pobočka se předvybere (web start).
  void configure(GearOrderData d) {
    if (state.data != null) return;
    _set((s) {
      s.data = d;
      s.month = DateTime(d.today.year, d.today.month);
      if (d.branches.length == 1) s.branchId = d.branches.first.id;
    });
  }

  /// Předvyplnění kontaktu z profilu (jen prázdná pole, web `auth.js`).
  void prefill(Map<String, dynamic>? p) {
    if (p == null) return;
    String v(String k) => '${p[k] ?? ''}'.trim();
    _set((s) {
      final c = s.contact;
      if (c.name.isEmpty) c.name = v('full_name');
      if (c.phone.isEmpty) c.phone = v('phone');
      if (c.street.isEmpty) c.street = v('street');
      if (c.city.isEmpty) c.city = v('city');
      if (c.zip.isEmpty) c.zip = v('zip');
      if (c.company.isEmpty) c.company = v('company_name');
      if (c.ico.isEmpty) c.ico = v('ico');
      if (c.dic.isEmpty) c.dic = v('dic');
      if (c.email.isEmpty) c.email = v('email').toLowerCase();
      if (v('company_name').isNotEmpty || v('ico').isNotEmpty) s.companyOn = true;
    });
  }

  // ---- pobočka a termín ----

  void setBranch(String id) {
    _set((s) {
      s.branchId = id;
      if (s.start != null && !s.rangeOk(s.start!, s.end ?? s.start!)) {
        s.start = s.end = null;
        s.open = false;
        s.calNote = const GearMsg('groErrClosed');
      }
    });
    _changed();
  }

  /// 1. klepnutí = 1 den (otevřený rozsah), 2. klepnutí na týž / pozdější
  /// den = konec (jen když jsou všechny dny volné a nejvýš `max_days`).
  void tapDay(DateTime day) {
    final d = gearDate(day);
    if (state.dayState(d) != GearDay.free) return;
    _set((s) {
      s.calNote = null;
      if (s.open && s.start != null && !d.isBefore(s.start!)) {
        if (!s.rangeOk(s.start!, d)) {
          s.calNote = const GearMsg('groErrClosed');
        } else if (gearCountDays(s.start!, d) > s.data!.cfg.maxDays) {
          s.calNote = GearMsg('groErrLong', {'n': s.data!.cfg.maxDays});
        } else {
          s.end = d;
          s.open = false;
        }
      } else {
        s.start = s.end = d;
        s.open = true;
      }
    });
    _changed();
  }

  void clearDates() {
    _set((s) {
      s.start = s.end = null;
      s.open = false;
      s.calNote = null;
    });
    _changed();
  }

  /// Měsíc kalendáře: od aktuálního nejvýš o 18 dopředu (web).
  void shiftMonth(int by) {
    final d = state.data;
    final m = state.month;
    if (d == null || m == null) return;
    final next = DateTime(m.year, m.month + by);
    final t0 = d.today.year * 12 + d.today.month - 1, cur = next.year * 12 + next.month - 1;
    if (cur < t0 || cur > t0 + 18) return;
    _set((s) => s.month = next);
  }

  bool canShiftMonth(int by) {
    final d = state.data, m = state.month;
    if (d == null || m == null) return false;
    final t0 = d.today.year * 12 + d.today.month - 1, cur = m.year * 12 + m.month - 1 + by;
    return cur >= t0 && cur <= t0 + 18;
  }

  void setPickupTime(String t) => _set((s) => s.pickupTime = t);

  void _changed() {
    _set((s) {
      s.drops = const [];
      _prune(s);
    });
    _loadAvail();
    _live();
  }

  void _prune(GearOrderState s) {
    final (sel, dropped) = gearPrune(s.prices, s.sel, s.isSelf, s.avail);
    s.sel = sel;
    if (dropped.isNotEmpty) {
      s.drops = [for (final (z, item) in dropped) GearMsg('groSizeDropped', {'size': z, 'item': item})];
    }
  }

  // ---- sklad (debounce 200 ms) ----

  void _loadAvail({bool force = false}) {
    final s = state;
    final key = s.branchId != null && s.start != null
        ? [s.branchId, gearIso(s.start!), gearIso(s.end ?? s.start!)].join('|')
        : '';
    if (!force && key == s.availKey) return;
    _set((x) {
      x.availKey = key;
      x.avail = null;
    });
    _availT?.cancel();
    if (key.isEmpty) return;
    final parts = key.split('|');
    _availT = Timer(availDelay, () async {
      try {
        final o = await api.availability(parts[0], parts[1], parts[2]);
        if (!mounted || state.availKey != key) return;
        _set((x) {
          x.avail = o['error'] == null && o['enabled'] == true ? o : null;
          _prune(x);
        });
        _live();
      } catch (_) {}
    });
  }

  void reloadAvail() => _loadAvail(force: true);

  // ---- výbava ----

  /// Komplet: vybere přesně jeho kusy (velikosti zůstanou), podruhé vše zruší.
  void toggleSet(String key) {
    final d = state.data;
    final set = d?.by[key];
    if (set == null) return;
    _set((s) {
      if (gearSetOn(set, s.prices, s.sel)) {
        s.sel = {};
      } else {
        s.sel = {for (final k in set.includes) if (d!.by.containsKey(k)) k: s.sel[k] ?? ''};
      }
      s.drops = const [];
    });
    _live();
  }

  void toggleItem(String key, bool on) {
    _set((s) {
      if (on) {
        s.sel[key] = s.sel[key] ?? '';
      } else {
        s.sel.remove(key);
      }
      s.drops = const [];
    });
    _live();
  }

  /// Klepnutí na velikost; totéž znovu = zrušit (web).
  void pickSize(String key, String size) {
    _set((s) {
      s.sel[key] = s.sel[key] == size ? '' : size;
      s.drops = const [];
    });
    _live();
  }

  /// Bez velikosti předvyplnit uloženou velikost z profilu, když jde.
  void preselectSize(String key, String? size) {
    final p = state.data?.by[key];
    if (p == null || size == null || size.isEmpty || (state.sel[key] ?? 'x').isNotEmpty) return;
    if (!gearSizeOk(p, size, state.isSelf, state.avail)) return;
    pickSize(key, size);
  }

  // ---- serverová cena + poukaz (debounce 350 ms) ----

  void _live({bool force = false}) {
    final s = state;
    if (!s.complete) {
      _quoteT?.cancel();
      _quoteN++;
      _set((x) {
        x.quoteKey = '';
        x.quoteWait = false;
        x.quoteRes = null;
        if (x.vcode.isNotEmpty) x.vstate = 'need';
      });
      return;
    }
    final items = s.itemsArg;
    final key = [s.branchId, gearIso(s.start!), gearIso(s.end!), jsonEncode(items), s.vcode].join('|');
    if (!force && s.quoteKey == key && (s.quoteWait || s.quoteRes != null)) return;
    final n = ++_quoteN;
    _set((x) {
      x.quoteKey = key;
      x.quoteWait = true;
      x.quoteRes = null;
      if (x.vcode.isNotEmpty) x.vstate = 'wait';
    });
    _quoteT?.cancel();
    final code = s.vcode;
    _quoteT = Timer(quoteDelay, () async {
      try {
        final o = await api.quote(s.branchId!, gearIso(s.start!), gearIso(s.end!), items, code.isEmpty ? null : code);
        if (!mounted || n != _quoteN) return;
        if (o['error'] == 'rpc_error') {
          _set((x) {
            x.quoteWait = false;
            x.quoteKey = '';
            if (x.vcode.isNotEmpty) x.vstate = '';
          });
          return;
        }
        var again = false;
        _set((x) {
          x.quoteWait = false;
          x.quoteRes = o;
          if (x.vcode.isNotEmpty) {
            if (o['error'] == 'bad_voucher') {
              x.vstate = 'bad';
              x.vcode = '';
              x.quoteKey = '';
              x.quoteRes = null;
              again = true;
            } else {
              x.vstate = o['error'] != null ? '' : (gearVoucherAmount(o) > 0 ? 'ok' : 'bad');
            }
          }
        });
        if (again) _live(force: true);
      } catch (_) {
        if (mounted && n == _quoteN) {
          _set((x) {
            x.quoteWait = false;
            x.quoteKey = '';
            x.quoteRes = null;
          });
        }
      }
    });
  }

  void setVoucherOn(bool on) {
    final had = state.vcode.isNotEmpty || state.vstate.isNotEmpty;
    _set((s) {
      s.voucherOn = on;
      if (!on) {
        s.vcode = '';
        s.vstate = '';
      }
    });
    if (!on && had) _live(force: true);
  }

  void applyVoucher(String raw) {
    final c = raw.trim().toUpperCase();
    if (c.isEmpty) return;
    _set((s) {
      s.vcode = c;
      s.vstate = s.complete ? 'wait' : 'need';
    });
    _live(force: true);
  }

  void removeVoucher() {
    _set((s) {
      s.vcode = '';
      s.vstate = '';
    });
    _live(force: true);
  }

  // ---- kontakt a souhlasy ----

  void setContact(void Function(GearContact c) f) => _set((s) => f(s.contact));
  void setCompanyOn(bool on) => _set((s) => s.companyOn = on);
  void setNote(String v) => _set((s) => s.note = v);
  void setVop(bool v) => _set((s) => s.vop = v);
  void setGdpr(bool v) => _set((s) => s.gdpr = v);
  void clearError() => _set((s) => s.error = null);

  // ---- odeslání (web submit.js) ----

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Kontrola ve webovém pořadí; null = vše v pořádku.
  GearMsg? validate() => _check(state);

  static GearMsg? _check(GearOrderState s) {
    if (s.data == null || s.branch == null) return const GearMsg('groErrBranch');
    if (s.start == null || s.end == null) return const GearMsg('groErrDates');
    final ks = s.keys;
    if (ks.isEmpty) return const GearMsg('groErrItems');
    for (final k in ks) {
      final p = s.data!.by[k]!;
      if (p.sizes.isNotEmpty && (s.sel[k] ?? '').isEmpty) return GearMsg('groErrSize', {'item': p.label});
    }
    final c = s.contact;
    if (c.name.trim().length < 3 || !_emailRe.hasMatch(c.email.trim().toLowerCase()) || c.phone.trim().length < 6) {
      return const GearMsg('groErrContact');
    }
    if (!s.vop || !s.gdpr) return const GearMsg('groErrAgree');
    return null;
  }

  Map<String, dynamic> createParams(String lang) {
    final s = state;
    final c = s.contact;
    final cust = <String, dynamic>{
      'name': c.name.trim(),
      'email': c.email.trim().toLowerCase(),
      'phone': c.phone.trim(),
      'street': c.street.trim(),
      'zip': c.zip.trim(),
      'city': c.city.trim(),
      if (s.companyOn) ...{'company': c.company.trim(), 'ico': c.ico.trim(), 'dic': c.dic.trim()},
    };
    return {
      'p_branch_id': s.branchId,
      'p_start': gearIso(s.start!),
      'p_end': gearIso(s.end!),
      'p_items': s.itemsArg,
      'p_customer': cust,
      'p_pickup_time': s.isSelf ? null : s.pickupTime,
      'p_return_time': null,
      'p_lang': lang,
      'p_note': s.note.trim().isEmpty ? null : s.note.trim(),
      'p_voucher_code': s.vcode.isEmpty ? null : s.vcode,
      'p_existing_booking_id': s.draftId,
      'p_consents': {'vop': true, 'gdpr': true},
    };
  }

  /// Založí (nebo přepíše nezaplacený koncept) rezervaci výbavy.
  Future<GearCreated?> submit(String lang) async {
    if (state.busy) return null;
    _set((s) => s.error = null);
    final bad = validate();
    if (bad != null) {
      _set((s) => s.error = bad);
      _formErr = true;
      return null;
    }
    _set((s) => s.busy = true);
    // Koncept s rozběhnutou platbou (3DS / „Platba se ověřuje“) nepřepisovat —
    // server by změnil cenu rezervace s otevřenou platbou → nová rezervace.
    final draft = state.draftId;
    if (draft != null && await _paymentPending(draft)) {
      if (!mounted) return null;
      await _saveDraft(null);
    }
    void done([GearMsg? m]) => _set((s) {
          s.busy = false;
          s.error = m;
        });
    Map<String, dynamic> o;
    try {
      o = await api.create(createParams(lang));
    } catch (_) {
      done(const GearMsg('groErrGeneric'));
      return null;
    }
    if (!mounted) return null;
    final id = '${o['booking_id'] ?? ''}';
    if (o['success'] == true && id.isNotEmpty) {
      await _saveDraft(id);
      done();
      return GearCreated(id, gearNum(o['amount'] ?? o['total']), reused: o['reused'] == true);
    }
    final e = '${o['error'] ?? ''}';
    final d = state.data!;
    if (e == 'out_of_stock') reloadAvail();
    if (e == 'bad_voucher') {
      _set((s) {
        s.vcode = '';
        s.vstate = 'bad';
      });
      _live(force: true);
    }
    final known = kGearCreateErr.containsKey(e) || e == 'email_mismatch' || e == 'out_of_stock';
    if (e.isNotEmpty && !known && e != 'rpc_error' && state.draftId != null) {
      await _saveDraft(null);
      _set((s) => s.busy = false);
      return submit(lang);
    }
    done(gearCreateErrMsg(o, d.by, d.cfg.maxDays, email: email));
    return null;
  }
}
