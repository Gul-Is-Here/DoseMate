import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

Color get _error => AppColors.error;

/// Asks before a destructive or hard-to-undo action. Resolves to true only
/// when the user confirms.
Future<bool> confirmAction({
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Keep',
  bool destructive = true,
}) async {
  // Dialogs pop their own route: Get.back would close an open snackbar
  // instead.
  final confirmed = await Get.dialog<bool>(
    Builder(
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: Text(
          title,
          style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
        ),
        content: Text(
          message,
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: destructive ? _error : AppColors.primary),
            ),
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}

/// Asks how many doses were added by a refill; null when cancelled.
Future<int?> askRefillCount(String medicineName) =>
    Get.dialog<int>(_RefillDialog(medicineName: medicineName));

/// Owns its text controller, so it is disposed only after the dialog's
/// closing animation has finished with it.
class _RefillDialog extends StatefulWidget {
  const _RefillDialog({required this.medicineName});

  final String medicineName;

  @override
  State<_RefillDialog> createState() => _RefillDialogState();
}

class _RefillDialogState extends State<_RefillDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_input.text.trim());
    final valid = value != null && value > 0 && value <= 9999;
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      title: Text(
        'Refill purchased',
        style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
      ),
      content: TextField(
        controller: _input,
        autofocus: true,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Doses added to ${widget.medicineName}',
          errorText: _input.text.isEmpty || valid
              ? null
              : 'Enter a number from 1 to 9999',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: valid ? () => Navigator.of(context).pop(value) : null,
          child: const Text('Add to supply'),
        ),
      ],
    );
  }
}
