import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/logo_header.dart';
import '../../auth/auth_provider.dart';
import '../nickname_provider.dart';
import 'menu_line.dart';

/// Top dark header bar: logo, pilot badge, search bar and hamburger menu.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16, MediaQuery.of(context).padding.top + 12, 16, 16,
      ),
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
          // Top row: logo + menu
          Row(
            children: [
              const Expanded(child: LogoRow()),
              const SizedBox(width: 12),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: MotoGoColors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => context.go(Routes.profile),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MotoGoColors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MenuLine(width: 16),
                      SizedBox(height: 4),
                      MenuLine(width: 12),
                      SizedBox(height: 4),
                      MenuLine(width: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pilot badge + search bar
          Row(
            children: [
              Flexible(
                child: _PilotBadge(profile: profile),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.go(Routes.search),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(context).tr('homeSearchPlaceholder'),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tappable pilot badge — shows nickname (or first name by default).
/// Tap to edit nickname without changing the real profile name.
class _PilotBadge extends ConsumerWidget {
  const _PilotBadge({required this.profile});

  final AsyncValue<Map<String, dynamic>?> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nickname = ref.watch(nicknameProvider);
    final fullName = profile.valueOrNull?['full_name'] as String?;
    final displayName = nickname ?? extractFirstName(fullName);

    return GestureDetector(
      onTap: () => _showNicknameDialog(context, ref, displayName),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MotoGoColors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(context).tr('homePilotLabel'),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
            Flexible(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNicknameDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final controller = TextEditingController(text: current);
    final fullName = profile.valueOrNull?['full_name'] as String?;
    final firstName = extractFirstName(fullName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          t(context).tr('homePilotLabel').replaceAll(':', '').trim(),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: Colors.black,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: firstName,
            hintStyle: TextStyle(
              color: Colors.black.withValues(alpha: 0.3),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(
                color: MotoGoColors.green.withValues(alpha: 0.4),
              ),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: MotoGoColors.green),
            ),
          ),
        ),
        actions: [
          // Reset to first name
          TextButton(
            onPressed: () {
              ref.read(nicknameProvider.notifier).clearNickname();
              Navigator.of(ctx).pop();
            },
            child: Text(
              'Reset',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Confirm
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                ref.read(nicknameProvider.notifier).setNickname(value);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text(
              'OK',
              style: TextStyle(
                color: MotoGoColors.green,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
