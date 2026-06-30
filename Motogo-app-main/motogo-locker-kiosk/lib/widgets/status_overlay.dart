import 'package:flutter/material.dart';
import '../theme.dart';

enum StatusKind { working, success, error }

/// Velký středový status (otevírám / otevřeno / chyba) přes celou obrazovku.
class StatusOverlay extends StatelessWidget {
  final StatusKind kind;
  final String title;
  final String? subtitle;
  final VoidCallback? onDismiss;

  const StatusOverlay({
    super.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = switch (kind) {
      StatusKind.success => MG.green,
      StatusKind.error => MG.red,
      StatusKind.working => MG.white,
    };
    final IconData icon = switch (kind) {
      StatusKind.success => Icons.lock_open_rounded,
      StatusKind.error => Icons.error_outline_rounded,
      StatusKind.working => Icons.sync_rounded,
    };

    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        alignment: Alignment.center,
        child: Container(
          width: 560,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 56),
          decoration: MG.glass(radius: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == StatusKind.working)
                const SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(strokeWidth: 6, color: MG.green),
                )
              else
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.15),
                    border: Border.all(color: accent, width: 3),
                  ),
                  child: Icon(icon, color: accent, size: 64),
                ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(color: MG.white, fontSize: 34, fontWeight: FontWeight.w900),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MG.white.withValues(alpha: 0.75), fontSize: 20),
                ),
              ],
              if (onDismiss != null && kind != StatusKind.working) ...[
                const SizedBox(height: 28),
                Text('Klepnutím zavřete',
                    style: TextStyle(color: MG.white.withValues(alpha: 0.4), fontSize: 15)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
