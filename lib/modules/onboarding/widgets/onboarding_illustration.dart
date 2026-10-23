import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.image, this.badge});

  /// Final-page variant: edge-to-edge image, bottom shade, no badge.
  const OnboardingIllustration.cover({super.key, required this.image})
    : badge = null;

  final String image;
  final String? badge;

  bool get _isCover => badge == null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_isCover ? 24 : 32),
          boxShadow: _isCover ? AppTheme.shadowMd : AppTheme.shadowSm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isCover)
              Image.asset(image, fit: BoxFit.cover)
            else
              Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(image, fit: BoxFit.contain),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _isCover
                      ? LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.onBackground.withValues(alpha: 0.1),
                            AppColors.onBackground.withValues(alpha: 0),
                            AppColors.onBackground.withValues(alpha: 0),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.primaryFixed.withValues(alpha: 0.2),
                            AppColors.primaryFixed.withValues(alpha: 0),
                            AppColors.surfaceContainerLow.withValues(
                              alpha: 0.6,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest.withValues(
                      alpha: 0.95,
                    ),
                    borderRadius: BorderRadius.circular(9999),
                    boxShadow: AppTheme.shadowSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        badge!,
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
