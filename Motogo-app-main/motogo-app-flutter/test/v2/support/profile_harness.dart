// Test stand-in for `ProfileScreen` (its initState calls `ref.invalidate`,
// which trips a debug-only inherited-widget assertion in tests — release is
// unaffected): builds the v2 hub view exactly like the seam does, from the
// same providers, with real controllers and local toggles.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/profile/v2/profile_groups_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_hub_v2.dart';
import 'package:motogo_app/features/profile/v2/profile_personal_v2.dart';

class PfHubHarness extends ConsumerStatefulWidget {
  final bool expanded;
  const PfHubHarness({super.key, this.expanded = false});

  @override
  ConsumerState<PfHubHarness> createState() => _PfHubHarnessState();
}

class _PfHubHarnessState extends ConsumerState<PfHubHarness> {
  final c = List.generate(9, (_) => TextEditingController());
  final cats = <String>{};
  DateTime? dob, exp;
  bool loaded = false;
  late bool open = widget.expanded;

  @override
  void dispose() {
    for (final x in c) {
      x.dispose();
    }
    super.dispose();
  }

  void _fill(Map<String, dynamic>? p) {
    if (p == null || loaded) return;
    loaded = true;
    const keys = ['full_name', 'email', 'phone', 'city', 'zip', 'street', 'country', 'id_number', 'license_number'];
    for (var i = 0; i < keys.length; i++) {
      c[i].text = '${p[keys[i]] ?? ''}';
    }
    dob = DateTime.tryParse('${p['date_of_birth'] ?? ''}');
    exp = DateTime.tryParse('${p['license_expiry'] ?? ''}');
    final g = p['license_group'];
    if (g is List) cats.addAll(g.map((e) => '$e'));
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(profileProvider);
    if (a.hasValue && !a.isLoading) _fill(a.valueOrNull);
    final loading = a.isLoading;
    final error = a.hasError ? a.error : null;
    final ready = !loading && error == null && loaded;
    void noop() {}
    final now = DateTime.now().year;
    return ProfileHubV2View(
      profile: a.valueOrNull,
      loading: loading,
      error: error,
      ready: ready,
      personalExpanded: open,
      onRetry: noop,
      onTogglePersonal: () => setState(() => open = !open),
      onPaymentMethods: noop,
      version: 'v4.2.0',
      form: PfFormData(
        name: c[0], email: c[1], phone: c[2], city: c[3], zip: c[4], street: c[5], country: c[6], idNum: c[7], licNum: c[8],
        dob: dob,
        licExp: exp,
        dobFirstYear: now - 100,
        dobLastYear: now - 18,
        licFirstYear: now,
        licLastYear: now + 20,
        licCategories: cats,
        licOptions: const ['AM', 'A1', 'A2', 'A', 'B'],
        onDob: (d) => setState(() => dob = d),
        onLicExp: (d) => setState(() => exp = d),
        onToggleCategory: (x) => setState(() => cats.contains(x) ? cats.remove(x) : cats.add(x)),
        onSave: noop,
      ),
      actions: PfGroupActions(
        onPermissions: noop, onNotif: noop, onPrivacy: noop, onPassword: noop, onLanguage: noop,
        onCurrency: noop, onFaq: noop, onLogout: noop, onDelete: noop,
      ),
    );
  }
}
