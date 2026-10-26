import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/app_colors.dart';

/// The app's snackbar: the inverse surface of the current theme, so it
/// stands out from the page and stays readable in light and dark.
SnackbarController showSnack(String title, String message) => Get.snackbar(
  title,
  message,
  backgroundColor: AppColors.inverseSurface,
  colorText: AppColors.inverseOnSurface,
  margin: const EdgeInsets.all(12),
  borderRadius: 16,
);
