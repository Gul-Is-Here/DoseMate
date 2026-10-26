import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// One reason shown in a [askPermission] dialog.
class PermissionPoint {
  const PermissionPoint(this.icon, this.text);

  final IconData icon;
  final String text;
}

/// Explains a system permission before the app asks for it: what it's
/// for, and (optionally) the switch to turn on on the next screen.
/// Resolves to true only when the user chooses to continue.
Future<bool> askPermission({
  required IconData icon,
  required String title,
  required String message,
  List<PermissionPoint> points = const [],
  String? switchLabel,
  String allowLabel = 'Continue',
  String laterLabel = 'Not now',
}) async {
  // Dialogs pop their own route: Get.back would close an open snackbar
  // instead.
  final ok = await Get.dialog<bool>(
    _PermissionDialog(
      icon: icon,
      title: title,
      message: message,
      points: points,
      switchLabel: switchLabel,
      allowLabel: allowLabel,
      laterLabel: laterLabel,
    ),
  );
  return ok ?? false;
}

class _PermissionDialog extends StatelessWidget {
  const _PermissionDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.points,
    required this.switchLabel,
    required this.allowLabel,
    required this.laterLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<PermissionPoint> points;
  final String? switchLabel;
  final String allowLabel;
  final String laterLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.selected,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 36, color: AppColors.onSelected),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (points.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (final p in points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(p.icon, size: 22, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.text,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (switchLabel case final label?) ...[
                const SizedBox(height: 16),
                _SwitchHint(label: label),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    shape: const StadiumBorder(),
                    textStyle: AppTextStyles.labelLg,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(allowLabel),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 48,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.onSurfaceVariant,
                    textStyle: AppTextStyles.labelLg,
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(laterLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A picture of the system switch to turn on next, so it's easy to spot.
class _SwitchHint extends StatelessWidget {
  const _SwitchHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'On the next screen, turn on $label',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ON THE NEXT SCREEN',
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Drawn, not a Switch: it only shows what to look for.
                Container(
                  width: 44,
                  height: 26,
                  padding: const EdgeInsets.all(3),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.onPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
