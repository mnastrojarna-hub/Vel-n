import 'package:flutter/material.dart';

/// Tab button used in the detail/card tab bar inside the reservation detail header.
class ResDetailTabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const ResDetailTabBtn({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: Colors.white.withValues(alpha: 0.3)) : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
