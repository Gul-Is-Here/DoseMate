import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/theme/app_theme.dart';

/// Full-width teal pill with a trailing arrow; shows a spinner while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.iconSize = 20,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(9999)),
        boxShadow: AppTheme.shadowMd,
      ),
      child: SizedBox(
        height: 56,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryContainer,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: AppColors.primaryContainer,
            disabledForegroundColor: AppColors.onPrimary,
            shape: const StadiumBorder(),
          ),
          onPressed: loading ? null : onPressed,
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.onPrimary,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Wraps instead of overflowing on narrow screens.
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelLg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: iconSize),
                  ],
                ),
        ),
      ),
    );
  }
}
