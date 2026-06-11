import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Section header label used between groups of menu items on the Profile screen.
class ProfileSectionTitle extends StatelessWidget {
  final String title;

  const ProfileSectionTitle({required this.title, super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: MotoGoColors.g400,
            letterSpacing: 0.5,
          ),
        ),
      );
}
