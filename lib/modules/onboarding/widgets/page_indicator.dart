import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class PageIndicator extends StatelessWidget {
  const PageIndicator({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: i == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current
                    ? AppColors.primary
                    : AppColors.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 6),
          Text(
            '${current + 1} of $count',
            style: AppTextStyles.labelSm.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
