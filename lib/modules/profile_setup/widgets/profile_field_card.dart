import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';

/// White rounded card with a small label over an icon + input row. The
/// shadow deepens while the input inside has focus.
class ProfileFieldCard extends StatelessWidget {
  const ProfileFieldCard({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    this.trailingLabel,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final String? trailingLabel;

  /// Text style shared by the inputs placed in [child].
  static final inputStyle = AppTextStyles.bodyLg.copyWith(
    color: AppColors.onSurface,
  );

  static InputDecoration inputDecoration(String hint) => InputDecoration(
    isCollapsed: true,
    border: InputBorder.none,
    hintText: hint,
    hintStyle: AppTextStyles.bodyLg.copyWith(
      color: AppColors.outline.withValues(alpha: 0.6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(48),
              boxShadow: focused ? AppTheme.shadowMd : AppTheme.shadowSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (trailingLabel != null)
                      Text(
                        trailingLabel!,
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: AppColors.outline),
                      const SizedBox(width: 8),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
