import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';

/// Illustration inside a white card, with "next visit" and clinic badges.
class VisitIllustrationCard extends StatelessWidget {
  const VisitIllustrationCard({super.key, required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.shadowMd,
      ),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(32),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(image, fit: BoxFit.cover),
              Positioned(
                top: 12,
                left: 12,
                child: _Badge(
                  icon: Icons.event,
                  iconBackground: AppColors.secondaryFixed,
                  iconColor: AppColors.onSecondaryFixed,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT VISIT',
                        style: AppTextStyles.labelSm.copyWith(
                          fontSize: 10,
                          height: 1,
                          letterSpacing: 0.03 * 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Oct 24 • 10:30 AM',
                        style: AppTextStyles.labelSm.copyWith(
                          height: 1.25,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _Badge(
                  icon: Icons.location_on,
                  iconBackground: AppColors.primaryFixed,
                  iconColor: AppColors.primary,
                  child: Text(
                    'City Care Clinic',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 14),
          ),
          const SizedBox(width: 8),
          child,
        ],
      ),
    );
  }
}
