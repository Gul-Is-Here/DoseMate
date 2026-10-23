import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../view_model/signup_view_model.dart';

class AccountForSelector extends StatelessWidget {
  const AccountForSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AccountFor selected;
  final ValueChanged<AccountFor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who is this account for?',
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _Option(
                  icon: Icons.person,
                  label: 'For Myself',
                  selected: selected == AccountFor.myself,
                  onTap: () => onChanged(AccountFor.myself),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Option(
                  icon: Icons.family_restroom,
                  label: 'Family / Caregiver',
                  selected: selected == AccountFor.caregiver,
                  onTap: () => onChanged(AccountFor.caregiver),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.surfaceContainerLowest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected ? AppTheme.shadowSm : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
