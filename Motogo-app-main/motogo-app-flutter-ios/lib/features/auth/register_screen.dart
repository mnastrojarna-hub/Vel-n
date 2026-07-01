import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/date_dropdown_field.dart';
import 'auth_provider.dart';
import 'widgets/toast_helper.dart';

/// 3-step registration — mirrors auth-register.js (regStep 1/2/3).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 1;
  bool _loading = false;
  // Směr přechodu mezi kroky → určuje, kam slide animace letí.
  bool _goingForward = true;

  // Step 1: Personal data
  final _fnameCtrl = TextEditingController();
  final _lnameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '+420 ');
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  // Step 2: Address
  final _streetCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  // Step 3: License
  final _idNumCtrl = TextEditingController();
  final _licNumCtrl = TextEditingController();
  final _licExpiryCtrl = TextEditingController();
  String _licGroup = 'A2';

  // Step 3: povinné souhlasy — tvrdý gate. Bez nich nelze dokončit registraci.
  // Zákazník je smí kdykoli odvolat v Nastavení; nová rezervace si je vyžádá znovu.
  bool _consentVop = false;
  bool _consentGdpr = false;

  void _next() {
    if (_step == 1 && !_validateStep1()) return;
    if (_step == 2 && !_validateStep2()) return;
    if (_step == 3) {
      if (!_validateStep3()) return;
      _doRegister();
      return;
    }
    setState(() {
      _goingForward = true;
      _step++;
    });
  }

  void _back() {
    if (_step > 1) {
      setState(() {
        _goingForward = false;
        _step--;
      });
    } else {
      context.backOr(Routes.login);
    }
  }

  /// Name validation — mirrors _regIsNameValid from auth-register.js.
  /// Unicode letters, spaces, hyphens, apostrophes; no 3+ identical chars.
  static bool _isNameValid(String? v) {
    if (v == null || v.length < 2) return false;
    // Only unicode letters, spaces, hyphens, apostrophes
    if (!RegExp(r"^[\p{Letter}\s'\-]+$", unicode: true).hasMatch(v)) return false;
    // Block gibberish: 3+ identical consecutive chars
    if (RegExp(r'(.)\1{2,}', caseSensitive: false).hasMatch(v)) return false;
    return true;
  }

  /// Parse Czech date "d. m. yyyy" — mirrors _regParseCzDate.
  static DateTime? _parseCzDate(String? v) {
    if (v == null || v.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})$').firstMatch(v.trim());
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// Czech "d. m. yyyy" → ISO "yyyy-MM-dd" for `date` columns (date_of_birth,
  /// license_expiry). Null if unparseable so a partial value never breaks the
  /// profile write.
  static String? _toIsoDate(String? v) {
    final d = _parseCzDate(v);
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  bool _validateStep1() {
    final fname = _fnameCtrl.text.trim();
    final lname = _lnameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;
    final dob = _dobCtrl.text.trim();

    if (!_isNameValid(fname)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('firstName'),
          message: t(context).tr('validNameMsg'));
      return false;
    }
    if (!_isNameValid(lname)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('lastName'),
          message: t(context).tr('validSurnameMsg'));
      return false;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).email,
          message: t(context).tr('validEmailMsg'));
      return false;
    }
    final digits = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+\d{8,14}$').hasMatch(digits)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('phone'),
          message: t(context).tr('validPhoneMsg'));
      return false;
    }
    // DOB: required, 18-99 years — mirrors auth-register.js
    final dobDate = _parseCzDate(dob);
    if (dobDate == null) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('dob'),
          message: t(context).tr('selectDob'));
      return false;
    }
    final today = DateTime.now();
    var age = today.year - dobDate.year;
    final mDiff = today.month - dobDate.month;
    if (mDiff < 0 || (mDiff == 0 && today.day < dobDate.day)) age--;
    if (age < 18) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('dob'),
          message: t(context).tr('mustBe18'));
      return false;
    }
    if (age > 99 || dobDate.isAfter(today)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('dob'),
          message: t(context).tr('validDobMsg'));
      return false;
    }
    if (pass.length < 8) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).password,
          message: t(context).tr('passwordMinLengthMsg'));
      return false;
    }
    if (pass != _passConfirmCtrl.text) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).password,
          message: t(context).tr('passwordsDoNotMatch'));
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (_cityCtrl.text.trim().length < 2) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('city'),
          message: t(context).tr('validCityMsg'));
      return false;
    }
    if (_streetCtrl.text.trim().length < 3) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('street'),
          message: t(context).tr('validStreetMsg'));
      return false;
    }
    return true;
  }

  bool _validateStep3() {
    if (_licNumCtrl.text.trim().length < 4) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('licenseNumber'),
          message: t(context).tr('validLicenseNumberMsg'));
      return false;
    }
    final licExpDate = _parseCzDate(_licExpiryCtrl.text.trim());
    if (licExpDate == null) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('licenseExpiry'),
          message: t(context).tr('selectLicenseExpiry'));
      return false;
    }
    // Must be valid at least 14 days from today — mirrors auth-register.js
    final minExpiry = DateTime.now().add(const Duration(days: 14));
    final minDate = DateTime(minExpiry.year, minExpiry.month, minExpiry.day);
    if (licExpDate.isBefore(minDate)) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('licenseExpiry'),
          message: t(context).tr('licenseMinValid'));
      return false;
    }
    // Povinné souhlasy — bez VOP a zpracování osobních údajů registraci nedokončíme.
    if (!_consentVop || !_consentGdpr) {
      showMotoGoToast(context, icon: '⚠️', title: t(context).tr('regConsentTitle'),
          message: t(context).tr('consentRequiredMsg'));
      return false;
    }
    return true;
  }

  Future<void> _doRegister() async {
    setState(() => _loading = true);

    final fullName = '${_fnameCtrl.text.trim()} ${_lnameCtrl.text.trim()}';
    final phone = _phoneCtrl.text.trim();

    final error = await AuthService.signUp(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      metadata: {
        'full_name': fullName,
        'phone': phone,
      },
      // Personal/address/license data written straight to `profiles` after
      // signup (the handle_new_user trigger only copies a subset, so without
      // this the profile, "osobní údaje" tab and license-group check stay
      // empty). Dates → ISO, license group → enum array.
      profile: {
        'full_name': fullName,
        'phone': phone,
        'date_of_birth': _toIsoDate(_dobCtrl.text.trim()),
        'id_number': _idNumCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'zip': _zipCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        'license_number': _licNumCtrl.text.trim(),
        'license_expiry': _toIsoDate(_licExpiryCtrl.text.trim()),
        'license_group': [_licGroup],
        // Povinné souhlasy zákazník aktivně odklikl v kroku 3 (gate ve
        // _validateStep3). Zapisujeme je explicitně, ať Velín ukazuje reálný
        // stav a nespoléháme na server-side default.
        'consent_vop': _consentVop,
        'consent_gdpr': _consentGdpr,
        'consent_data_processing': _consentGdpr,
      },
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).tr('registerError'), message: error);
    } else {
      // Uvítací oslava (motorka + jiskry) místo pouhého toastu — první dojem
      // z appky. Po doběhnutí/tapnutí pokračujeme na domovskou obrazovku.
      await MotoWelcomeOverlay.show(
        context,
        title: t(context).tr('registerComplete'),
        subtitle: t(context).tr('welcomeToMotoGo'),
      );
      if (!mounted) return;
      context.go(Routes.home);
    }
  }

  @override
  void dispose() {
    _fnameCtrl.dispose(); _lnameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _passCtrl.dispose(); _passConfirmCtrl.dispose(); _dobCtrl.dispose();
    _streetCtrl.dispose(); _zipCtrl.dispose(); _cityCtrl.dispose(); _countryCtrl.dispose();
    _idNumCtrl.dispose(); _licNumCtrl.dispose(); _licExpiryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  PressableScale(
                    pressedScale: 0.88,
                    onTap: _back,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [MotoGoColors.green, MotoGoColors.greenDark],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: MotoGoColors.green.withValues(alpha: 0.4),
                            blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    t(context).tr('registerTitle'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black),
                  ),
                  const Spacer(),
                  // „Krok X/3" — jasná orientace v průvodci.
                  Text('${_step}/3',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.greenDark)),
                ],
              ),
            ),
            // Step indicators (animované pruhy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: List.generate(3, (i) {
                  final s = i + 1;
                  final active = s == _step;
                  final done = s < _step;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      height: active ? 7 : 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        gradient: (done || active)
                            ? const LinearGradient(colors: [MotoGoColors.green, MotoGoColors.greenDark])
                            : null,
                        color: (done || active) ? null : MotoGoColors.g200,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: active
                            ? [BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.5), blurRadius: 8)]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Content — přechod mezi kroky se animuje (slide + fade)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                      boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 340),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        final offset = _goingForward
                            ? const Offset(0.18, 0)
                            : const Offset(-0.18, 0);
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(begin: offset, end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: _buildStep(),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: PressableScale(
                enabled: !_loading,
                child: ElevatedButton(
                onPressed: _loading ? null : _next,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_step == 3 ? Icons.check_circle : Icons.arrow_forward, size: 18),
                        const SizedBox(width: 8),
                        Text(_step == 3 ? t(context).tr('finishRegistration') : t(context).tr('continueBtn')),
                      ]),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    // Klíč podle kroku → AnimatedSwitcher pozná změnu a přehraje slide+fade.
    final Widget content;
    switch (_step) {
      case 1: content = _step1(); break;
      case 2: content = _step2(); break;
      case 3: content = _step3(); break;
      default: content = const SizedBox.shrink();
    }
    return KeyedSubtree(key: ValueKey(_step), child: content);
  }

  /// Sloupec, jehož děti naběhnou postupně (fade + slide-up) — zážitek z
  /// vyplňování. Re-spustí se při každé změně kroku (nový klíč z [_buildStep]).
  Widget _revealColumn(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++)
            StaggeredReveal(index: i, child: children[i]),
        ],
      );

  Widget _step1() => _revealColumn([
      Text(t(context).tr('regStep1Title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      Text(t(context).tr('regStep1Subtitle'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: TextField(controller: _fnameCtrl, decoration: InputDecoration(labelText: t(context).tr('firstName')), autofillHints: const [AutofillHints.givenName])),
          const SizedBox(width: 9),
          Expanded(child: TextField(controller: _lnameCtrl, decoration: InputDecoration(labelText: t(context).tr('lastName')), autofillHints: const [AutofillHints.familyName])),
        ],
      ),
      const SizedBox(height: 9),
      TextField(controller: _emailCtrl, decoration: InputDecoration(labelText: t(context).email), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
      const SizedBox(height: 9),
      TextField(controller: _phoneCtrl, decoration: InputDecoration(labelText: t(context).tr('phone')), keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber]),
      const SizedBox(height: 9),
      DateDropdownField(
        controller: _dobCtrl,
        label: t(context).tr('dob'),
        firstYear: DateTime.now().year - 100,
        lastYear: DateTime.now().year - 15,
        yearsDescending: true,
      ),
      const SizedBox(height: 9),
      TextField(controller: _passCtrl, decoration: InputDecoration(labelText: t(context).tr('passwordMin8')), obscureText: true),
      const SizedBox(height: 9),
      TextField(controller: _passConfirmCtrl, decoration: InputDecoration(labelText: t(context).tr('passwordConfirm')), obscureText: true),
  ]);

  Widget _step2() => _revealColumn([
      Text(t(context).tr('regStep2Title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      Text(t(context).tr('regStep2Subtitle'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(flex: 2, child: TextField(controller: _cityCtrl, decoration: InputDecoration(labelText: t(context).tr('city')))),
          const SizedBox(width: 9),
          Expanded(child: TextField(controller: _zipCtrl, decoration: InputDecoration(labelText: t(context).tr('zip')), keyboardType: TextInputType.number)),
        ],
      ),
      const SizedBox(height: 9),
      TextField(controller: _streetCtrl, decoration: InputDecoration(labelText: t(context).tr('street'))),
      const SizedBox(height: 9),
      // Stát bydliště = volný text → zákazník napíše JAKÝKOLI stát ve svém
      // jazyce (ne jen jazyky appky, žádné předvolby). Není to jazyk.
      TextField(
        controller: _countryCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: t(context).tr('countryLabel')),
        autofillHints: const [AutofillHints.countryName],
      ),
  ]);

  Widget _step3() => _revealColumn([
      Text(t(context).tr('regStep3Title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      Text(t(context).tr('regStep3Subtitle'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 12),
      TextField(controller: _idNumCtrl, decoration: InputDecoration(labelText: t(context).tr('idNumberFull'))),
      const SizedBox(height: 9),
      TextField(controller: _licNumCtrl, decoration: InputDecoration(labelText: t(context).tr('licenseNumber'))),
      const SizedBox(height: 9),
      DateDropdownField(
        controller: _licExpiryCtrl,
        label: t(context).tr('licenseExpiry'),
        firstYear: DateTime.now().year,
        lastYear: DateTime.now().year + 20,
      ),
      const SizedBox(height: 9),
      DropdownButtonFormField<String>(
        value: _licGroup,
        dropdownColor: Colors.white,
        decoration: InputDecoration(labelText: t(context).tr('licenseCategory')),
        items: [
          DropdownMenuItem(value: 'A2', child: Text(t(context).tr('licA2Desc'))),
          DropdownMenuItem(value: 'A', child: Text(t(context).tr('licADesc'))),
        ],
        onChanged: (v) => setState(() => _licGroup = v ?? _licGroup),
      ),
      const SizedBox(height: 14),
      Container(height: 1, color: MotoGoColors.g200),
      const SizedBox(height: 10),
      Text(t(context).tr('regConsentTitle'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      _consentCheckbox(t(context).tr('consentTermsVop'), _consentVop,
          (v) => setState(() => _consentVop = v)),
      _consentCheckbox(t(context).tr('consentPersonalData'), _consentGdpr,
          (v) => setState(() => _consentGdpr = v)),
  ]);

  /// Zaškrtávací řádek pro povinný souhlas (VOP / zpracování osobních údajů).
  Widget _consentCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22, height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: value ? MotoGoColors.green : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: value ? MotoGoColors.green : MotoGoColors.g300, width: 2),
            ),
            child: value ? const Icon(Icons.check, size: 15, color: Colors.black) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
          ),
        ]),
      ),
    );
  }
}
