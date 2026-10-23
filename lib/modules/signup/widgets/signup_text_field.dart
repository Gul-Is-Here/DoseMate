import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';

/// Tinted input that turns white with a teal ring while focused.
class SignupTextField extends StatefulWidget {
  const SignupTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.onToggleObscure,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;

  /// Shows the visibility toggle when set.
  final VoidCallback? onToggleObscure;

  @override
  State<SignupTextField> createState() => _SignupTextFieldState();
}

class _SignupTextFieldState extends State<SignupTextField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          decoration: BoxDecoration(
            color: focused
                ? AppColors.surfaceContainerLowest
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused ? AppColors.primaryContainer : Colors.transparent,
              width: 2,
            ),
            boxShadow: AppTheme.shadowSm,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textAlignVertical: TextAlignVertical.center,
            style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurface),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: AppTextStyles.bodyLg.copyWith(
                color: AppColors.outline,
              ),
              prefixIcon: Icon(widget.icon, size: 18, color: AppColors.outline),
              prefixIconConstraints: const BoxConstraints(minWidth: 46),
              suffixIcon: widget.onToggleObscure == null
                  ? null
                  : IconButton(
                      onPressed: widget.onToggleObscure,
                      icon: Icon(
                        widget.obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: AppColors.outline,
                      ),
                    ),
              contentPadding: const EdgeInsets.only(right: 16),
            ),
          ),
        ),
      ],
    );
  }
}
