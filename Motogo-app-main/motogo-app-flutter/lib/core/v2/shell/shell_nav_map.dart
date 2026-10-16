import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../flag/v2_scope.dart';

/// Tab roots of the v2 nav (index = tab): Domů · Motorky · Rezervace ·
/// Trasy · Profil.
const List<String> kV2TabRoutes = kV2TabRoots;

String _path(String location) => Uri.tryParse(location)?.path ?? location;

/// Which tab is highlighted for [location] (PLAN §1.10).
int v2TabIndexFor(String location) {
  final p = _path(location);
  if (p == '/search' || p.startsWith('/moto') || p == '/booking' || p == '/payment') return 1;
  if (p.startsWith('/reservations') || p.startsWith('/sos')) return 2;
  if (p.startsWith('/routes') || p.startsWith('/places-map') || p.startsWith('/pois')) return 3;
  if (p == '/profile' ||
      p.startsWith('/messages') ||
      p == '/invoices' ||
      p == '/contracts' ||
      p.startsWith('/pobocky') ||
      p == '/loyalty' ||
      p == '/permissions' ||
      p.startsWith('/shop') ||
      p == '/cart' ||
      p == '/checkout' ||
      p == '/voucher' ||
      p == '/ai-agent') {
    return 4;
  }
  return 0;
}

final RegExp _resEdit = RegExp(r'^/reservations/[^/]+/edit$');
final RegExp _thread = RegExp(r'^/messages/[^/]+$');
final RegExp _routeDetail = RegExp(r'^/routes/[^/]+$');

/// Focused flows hide the nav (the screen's back control is the way out;
/// system back is unchanged).
bool v2NavHiddenFor(String location) {
  final p = _path(location);
  return p.startsWith('/moto/') ||
      p == '/booking' ||
      p == '/payment' ||
      p == '/sos/payment' ||
      _resEdit.hasMatch(p) ||
      p == '/ai-agent' ||
      _thread.hasMatch(p) ||
      p == '/checkout';
}

/// Routes where the floating AI button is hidden (docked into the screen's
/// dock, map controls, SOS priority, the chat itself…).
bool v2FabHiddenFor(String location) {
  final p = _path(location);
  return v2NavHiddenFor(p) ||
      p.startsWith('/sos') ||
      p == '/cart' ||
      p == '/routes' ||
      p == '/routes-list' ||
      _routeDetail.hasMatch(p) ||
      p == '/places-map' ||
      p == '/routes-map';
}

/// Re-tap of the active tab: (tab index, sequence) — `MgPage` scrolls to top.
final v2TabReselectProvider = StateProvider<(int, int)>((_) => (-1, 0));
