import 'package:flutter/material.dart';

/// Simple text field used in the personal info form on the Profile screen.
class ProfileField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final TextInputType type;
  final bool readOnly;

  const ProfileField({
    required this.ctrl,
    required this.label,
    this.type = TextInputType.text,
    this.readOnly = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          readOnly: readOnly,
          enableInteractiveSelection: true,
          style: readOnly ? const TextStyle(color: Color(0xFF6B8C7A)) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
