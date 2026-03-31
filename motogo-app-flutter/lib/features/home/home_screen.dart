import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../auth/auth_provider.dart';

/// Home screen — mirrors s-home from templates-screens.js.
/// Shows greeting, active reservation banner, and quick actions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: MotoGoColors.dark,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: MotoGoColors.green,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text('🏍️', style: TextStyle(fontSize: 20)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MOTO GO 24',
                                  style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900,
                                    color: Colors.white, letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  'PŮJČOVNA MOTOREK',
                                  style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w700,
                                    color: Colors.white38, letterSpacing: 2.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: MotoGoColors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => context.go(Routes.profile),
                              child: Container(
                                width: 34, height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _MenuLine(width: 16),
                                    SizedBox(height: 3),
                                    _MenuLine(width: 12),
                                    SizedBox(height: 3),
                                    _MenuLine(width: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: MotoGoColors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'Pilot: ',
                                style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700,
                                  color: Colors.white54, letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                profile.valueOrNull?['full_name'] ?? 'Pilot',
                                style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Active reservation banner (placeholder — Part 5 will implement)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: () => context.go(Routes.search),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                      boxShadow: [
                        BoxShadow(
                          color: MotoGoColors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Text('🏍️', style: TextStyle(fontSize: 24)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Žádná aktivní rezervace',
                                style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800,
                                  color: MotoGoColors.black,
                                ),
                              ),
                              Text(
                                'Zarezervujte si motorku',
                                style: TextStyle(fontSize: 12, color: MotoGoColors.g400),
                              ),
                            ],
                          ),
                        ),
                        Text('›', style: TextStyle(fontSize: 18, color: MotoGoColors.g400)),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Quick actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _QuickAction(
                      icon: '📅',
                      label: 'Rezervovat',
                      onTap: () => context.go(Routes.search),
                    ),
                    const SizedBox(width: 10),
                    _QuickAction(
                      icon: '🤖',
                      label: 'AI Agent',
                      onTap: () => context.push(Routes.aiAgent),
                    ),
                    const SizedBox(width: 10),
                    _QuickAction(
                      icon: '🆘',
                      label: 'SOS',
                      onTap: () => context.push(Routes.sos),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLine extends StatelessWidget {
  final double width;
  const _MenuLine({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            boxShadow: [
              BoxShadow(
                color: MotoGoColors.black.withValues(alpha: 0.06),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: MotoGoColors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
