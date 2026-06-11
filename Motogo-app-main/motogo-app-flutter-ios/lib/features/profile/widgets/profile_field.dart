import 'package:flutter/material.dart';

/// Simple text field used in the personal info form on the Profile screen.
class ProfileField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final TextInputType type;

  const ProfileField({
    required this.ctrl,
    required this.label,
    this.type = TextInputType.text,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
