import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Round profile photo: a just-picked [file] wins over the saved [url];
/// with neither (or a failed load) it shows a person icon.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.size, this.url, this.file});

  final double size;
  final String? url;
  final File? file;

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(
      Icons.person,
      size: size * 0.55,
      color: AppColors.outline,
    );
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: switch ((file, url)) {
        (final File file, _) => Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
        ),
        (_, final String url) => Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          errorBuilder: (_, _, _) => placeholder,
        ),
        _ => placeholder,
      },
    );
  }
}
