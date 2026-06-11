import 'package:flutter/material.dart';
import 'theme.dart';

/// Temporary placeholder for screens not yet migrated.
/// Will be replaced by real implementations in Parts 2-10.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: MotoGoColors.dark,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.black,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Migrace v dalších fázích',
              style: TextStyle(
                fontSize: 13,
                color: MotoGoColors.g400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
