import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Plain progress dots without the pill background or "x of y" label.
class DotIndicator extends StatelessWidget {
  const DotIndicator({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.primaryContainer
                  : AppColors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ],
      ],
    );
  }
}
