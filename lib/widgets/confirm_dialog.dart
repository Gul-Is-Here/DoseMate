import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

const _error = Color(0xFFBA1A1A);

/// Asks before a destructive or hard-to-undo action. Resolves to true only
/// when the user confirms.
Future<bool> confirmAction({
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  // Dialogs pop their own route: Get.back would close an open snackbar
  // instead.
  final confirmed = await Get.dialog<bool>(
    Builder(
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
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
            child: const Text('Keep'),
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
Future<int?> askRefillCount(String medicineName) async {
  final input = TextEditingController();
  final count = await Get.dialog<int>(
    StatefulBuilder(
      builder: (context, setState) {
        final value = int.tryParse(input.text.trim());
        final valid = value != null && value > 0 && value <= 9999;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Refill purchased',
            style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
          ),
          content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Doses added to $medicineName',
              errorText: input.text.isEmpty || valid
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
      },
    ),
  );
  input.dispose();
  return count;
}
