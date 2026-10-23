import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/onboarding_page.dart';

/// Several features grouped inside a single white card.
class FeatureListCard extends StatelessWidget {
  const FeatureListCard({super.key, required this.features});

  final List<OnboardingFeature> features;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          for (final (i, feature) in features.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            _FeatureRow(feature: feature),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final OnboardingFeature feature;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: feature.iconBackground,
            shape: BoxShape.circle,
          ),
          child: Icon(feature.icon, color: feature.iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                feature.description,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  height: 1.625,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
