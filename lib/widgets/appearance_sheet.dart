import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/theme/theme_controller.dart';

/// System, Light or Dark. A choice applies at once and is remembered on
/// this device.
class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key});

  static Future<void> show() => Get.bottomSheet(
    const AppearanceSheet(),
    isScrollControlled: true,
    // The sheet paints its own background (see build), so a switch made
    // here recolours it at once.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
  );

  static String label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Match system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static IconData icon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final appearance = Get.find<ThemeController>();
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  'Appearance',
                  style: AppTextStyles.titleLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Match system follows your phone’s light or dark setting.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Obx(() {
                final current = appearance.mode.value;
                return RadioGroup<ThemeMode>(
                  groupValue: current,
                  onChanged: (m) {
                    if (m != null) appearance.setMode(m);
                  },
                  child: Column(
                    children: [
                      for (final m in ThemeMode.values)
                        RadioListTile<ThemeMode>(
                          key: ValueKey('appearance-${m.name}'),
                          value: m,
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            icon(m),
                            color: m == current
                                ? AppColors.onSelected
                                : AppColors.onSurfaceVariant,
                          ),
                          title: Text(
                            label(m),
                            style: AppTextStyles.labelLg.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
