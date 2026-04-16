import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
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
  String _country = 'Česká republika';

  // Step 3: License
  final _licNumCtrl = TextEditingController();
  final _licExpiryCtrl = TextEditingController();
  String _licGroup = 'A2';

  void _next() {
    if (_step == 1 && !_validateStep1()) return;
    if (_step == 2 && !_validateStep2()) return;
    if (_step == 3) {
      if (!_validateStep3()) return;
      _doRegister();
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step > 1) {
      setState(() => _step--);
    } else {
      context.pop();
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
    return true;
  }

  Future<void> _doRegister() async {
    setState(() => _loading = true);

    final error = await AuthService.signUp(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      metadata: {
        'full_name': '${_fnameCtrl.text.trim()} ${_lnameCtrl.text.trim()}',
        'phone': _phoneCtrl.text.trim(),
        'date_of_birth': _dobCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'zip': _zipCtrl.text.trim(),
        'country': _country,
        'license_number': _licNumCtrl.text.trim(),
        'license_expiry': _licExpiryCtrl.text.trim(),
        'license_group': _licGroup,
      },
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      showMotoGoToast(context, icon: '✗', title: t(context).tr('registerError'), message: error);
    } else {
      showMotoGoToast(context, icon: '✓', title: t(context).tr('registerComplete'), message: t(context).tr('welcomeToMotoGo'));
      context.go(Routes.home);
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ctrl == _dobCtrl ? DateTime(now.year - 25) : now.add(const Duration(days: 365)),
      firstDate: ctrl == _dobCtrl ? DateTime(1930) : now,
      lastDate: ctrl == _dobCtrl ? now : DateTime(2040),
      locale: const Locale('cs'),
    );
    if (picked != null) {
      ctrl.text = '${picked.day}. ${picked.month}. ${picked.year}';
    }
  }

  @override
  void dispose() {
    _fnameCtrl.dispose(); _lnameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _passCtrl.dispose(); _passConfirmCtrl.dispose(); _dobCtrl.dispose();
    _streetCtrl.dispose(); _zipCtrl.dispose(); _cityCtrl.dispose();
    _licNumCtrl.dispose(); _licExpiryCtrl.dispose();
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
                  GestureDetector(
                    onTap: _back,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: MotoGoColors.green,
                        borderRadius: BorderRadius.circular(10),
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
                ],
              ),
            ),
            // Step indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: List.generate(3, (i) {
                  final s = i + 1;
                  final active = s == _step;
                  final done = s < _step;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: done ? MotoGoColors.green : (active ? MotoGoColors.greenDark : MotoGoColors.g200),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                    boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)],
                  ),
                  child: _buildStep(),
                ),
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1: return _step1();
      case 2: return _step2();
      case 3: return _step3();
      default: return const SizedBox.shrink();
    }
  }

  Widget _step1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
      GestureDetector(
        onTap: () => _pickDate(_dobCtrl),
        child: AbsorbPointer(
          child: TextField(controller: _dobCtrl, decoration: InputDecoration(labelText: t(context).tr('dob'), suffixIcon: const Icon(Icons.calendar_today, size: 18))),
        ),
      ),
      const SizedBox(height: 9),
      TextField(controller: _passCtrl, decoration: InputDecoration(labelText: t(context).tr('passwordMin8')), obscureText: true),
      const SizedBox(height: 9),
      TextField(controller: _passConfirmCtrl, decoration: InputDecoration(labelText: t(context).tr('passwordConfirm')), obscureText: true),
    ],
  );

  Widget _step2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
      DropdownButtonFormField<String>(
        value: _country,
        decoration: InputDecoration(labelText: t(context).tr('countryLabel')),
        items: [
          DropdownMenuItem(value: 'Česká republika', child: Text(t(context).tr('countryCZ'))),
          DropdownMenuItem(value: 'Slovenská republika', child: Text(t(context).tr('countrySK'))),
          DropdownMenuItem(value: 'Německo', child: Text(t(context).tr('countryDE'))),
          DropdownMenuItem(value: 'Rakousko', child: Text(t(context).tr('countryAT'))),
          DropdownMenuItem(value: 'Polsko', child: Text(t(context).tr('countryPL'))),
        ],
        onChanged: (v) => setState(() => _country = v ?? _country),
      ),
    ],
  );

  Widget _step3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t(context).tr('regStep3Title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 2),
      Text(t(context).tr('regStep3Subtitle'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 12),
      TextField(controller: _licNumCtrl, decoration: InputDecoration(labelText: t(context).tr('licenseNumber'))),
      const SizedBox(height: 9),
      GestureDetector(
        onTap: () => _pickDate(_licExpiryCtrl),
        child: AbsorbPointer(
          child: TextField(controller: _licExpiryCtrl, decoration: InputDecoration(labelText: t(context).tr('licenseExpiry'), suffixIcon: const Icon(Icons.calendar_today, size: 18))),
        ),
      ),
      const SizedBox(height: 9),
      DropdownButtonFormField<String>(
        value: _licGroup,
        decoration: InputDecoration(labelText: t(context).tr('licenseCategory')),
        items: [
          DropdownMenuItem(value: 'A2', child: Text(t(context).tr('licA2Desc'))),
          DropdownMenuItem(value: 'A', child: Text(t(context).tr('licADesc'))),
        ],
        onChanged: (v) => setState(() => _licGroup = v ?? _licGroup),
      ),
    ],
  );
}
