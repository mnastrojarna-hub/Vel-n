import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
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

  bool _validateStep1() {
    final fname = _fnameCtrl.text.trim();
    final lname = _lnameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text;
    final dob = _dobCtrl.text.trim();

    if (fname.length < 2) {
      showMotoGoToast(context, icon: '⚠️', title: 'Jméno', message: 'Min. 2 písmena');
      return false;
    }
    if (lname.length < 2) {
      showMotoGoToast(context, icon: '⚠️', title: 'Příjmení', message: 'Min. 2 písmena');
      return false;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      showMotoGoToast(context, icon: '⚠️', title: 'Email', message: 'Neplatný email');
      return false;
    }
    final digits = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+\d{8,14}$').hasMatch(digits)) {
      showMotoGoToast(context, icon: '⚠️', title: 'Telefon', message: 'Mezinárodní formát (+420...)');
      return false;
    }
    if (dob.isEmpty) {
      showMotoGoToast(context, icon: '⚠️', title: 'Narození', message: 'Vyberte datum narození');
      return false;
    }
    if (pass.length < 8) {
      showMotoGoToast(context, icon: '⚠️', title: 'Heslo', message: 'Min. 8 znaků');
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (_cityCtrl.text.trim().length < 2) {
      showMotoGoToast(context, icon: '⚠️', title: 'Město', message: 'Min. 2 znaky');
      return false;
    }
    if (_streetCtrl.text.trim().length < 3) {
      showMotoGoToast(context, icon: '⚠️', title: 'Ulice', message: 'Min. 3 znaky');
      return false;
    }
    return true;
  }

  Future<void> _doRegister() async {
    if (_licNumCtrl.text.trim().length < 4) {
      showMotoGoToast(context, icon: '⚠️', title: 'ŘP', message: 'Min. 4 znaky');
      return;
    }
    if (_licExpiryCtrl.text.isEmpty) {
      showMotoGoToast(context, icon: '⚠️', title: 'ŘP platnost', message: 'Vyberte datum');
      return;
    }

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
      showMotoGoToast(context, icon: '✗', title: 'Chyba registrace', message: error);
    } else {
      showMotoGoToast(context, icon: '✓', title: 'Registrace dokončena!', message: 'Vítejte v MotoGo24');
      context.go(Routes.home);
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ctrl == _dobCtrl ? DateTime(now.year - 25) : now.add(const Duration(days: 365)),
      firstDate: DateTime(1930),
      lastDate: DateTime(2040),
      locale: const Locale('cs'),
    );
    if (picked != null) {
      ctrl.text = '${picked.day}. ${picked.month}. ${picked.year}';
    }
  }

  @override
  void dispose() {
    _fnameCtrl.dispose(); _lnameCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _passCtrl.dispose(); _dobCtrl.dispose();
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                        child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _step == 1 ? 'Zpět na přihlášení' : 'Zpět',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: MotoGoColors.g400),
                  ),
                ],
              ),
            ),
            // Step indicators
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
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
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: _loading ? null : _next,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_step == 3 ? 'DOKONČIT REGISTRACI' : 'POKRAČOVAT'),
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
      const Text('Osobní údaje', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 4),
      const Text('Krok 1 ze 3', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 16),
      TextField(controller: _fnameCtrl, decoration: const InputDecoration(labelText: 'Jméno'), autofillHints: const [AutofillHints.givenName]),
      const SizedBox(height: 10),
      TextField(controller: _lnameCtrl, decoration: const InputDecoration(labelText: 'Příjmení'), autofillHints: const [AutofillHints.familyName]),
      const SizedBox(height: 10),
      TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'E-mail'), keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email]),
      const SizedBox(height: 10),
      TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Telefon'), keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber]),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => _pickDate(_dobCtrl),
        child: AbsorbPointer(
          child: TextField(controller: _dobCtrl, decoration: const InputDecoration(labelText: 'Datum narození', suffixIcon: Icon(Icons.calendar_today, size: 18))),
        ),
      ),
      const SizedBox(height: 10),
      TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Heslo (min. 8 znaků)'), obscureText: true),
    ],
  );

  Widget _step2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Adresa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 4),
      const Text('Krok 2 ze 3', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 16),
      TextField(controller: _streetCtrl, decoration: const InputDecoration(labelText: 'Ulice a č.p. / č.o.')),
      const SizedBox(height: 10),
      TextField(controller: _zipCtrl, decoration: const InputDecoration(labelText: 'PSČ'), keyboardType: TextInputType.number),
      const SizedBox(height: 10),
      TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'Obec / město')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _country,
        decoration: const InputDecoration(labelText: 'Stát'),
        items: const [
          DropdownMenuItem(value: 'Česká republika', child: Text('Česká republika')),
          DropdownMenuItem(value: 'Slovensko', child: Text('Slovensko')),
          DropdownMenuItem(value: 'Německo', child: Text('Německo')),
          DropdownMenuItem(value: 'Rakousko', child: Text('Rakousko')),
          DropdownMenuItem(value: 'Polsko', child: Text('Polsko')),
        ],
        onChanged: (v) => setState(() => _country = v ?? _country),
      ),
    ],
  );

  Widget _step3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Řidičský průkaz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
      const SizedBox(height: 4),
      const Text('Krok 3 ze 3', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
      const SizedBox(height: 16),
      TextField(controller: _licNumCtrl, decoration: const InputDecoration(labelText: 'Číslo ŘP')),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => _pickDate(_licExpiryCtrl),
        child: AbsorbPointer(
          child: TextField(controller: _licExpiryCtrl, decoration: const InputDecoration(labelText: 'Platnost ŘP do', suffixIcon: Icon(Icons.calendar_today, size: 18))),
        ),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _licGroup,
        decoration: const InputDecoration(labelText: 'Kategorie ŘP'),
        items: const [
          DropdownMenuItem(value: 'AM', child: Text('AM')),
          DropdownMenuItem(value: 'A1', child: Text('A1')),
          DropdownMenuItem(value: 'A2', child: Text('A2')),
          DropdownMenuItem(value: 'A', child: Text('A')),
          DropdownMenuItem(value: 'B', child: Text('B')),
        ],
        onChanged: (v) => setState(() => _licGroup = v ?? _licGroup),
      ),
    ],
  );
}
