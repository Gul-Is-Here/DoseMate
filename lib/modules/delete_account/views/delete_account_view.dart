import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../widgets/app_shell.dart';
import '../view_model/delete_account_view_model.dart';

const _radius = 24.0;

/// Opened from Settings. Says exactly what goes, confirms it's the account
/// holder, then shows each step until the account is gone.
class DeleteAccountView extends GetView<DeleteAccountViewModel> {
  const DeleteAccountView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => PopScope(
        // No way out halfway through.
        canPop: !controller.busy,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          body: Column(
            children: [
              const AppBackBar(title: 'Delete Account'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(kMargin, 16, kMargin, 32),
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Delete your account',
                        style: AppTextStyles.headlineLgMobile.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This permanently deletes your DoseMate account. It '
                      'can’t be undone.',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: kSpaceLg),
                    const _WhatGoes(),
                    const SizedBox(height: kSpaceMd),
                    _Note(
                      icon: Icons.file_download_outlined,
                      text:
                          'Want a copy first? Export your dose history as a '
                          'PDF or CSV from History before you continue.',
                    ),
                    const SizedBox(height: kSpaceLg),
                    if (controller.busy)
                      const _Progress()
                    else ...[
                      const _Confirm(),
                      if (controller.error.value case final message?) ...[
                        const SizedBox(height: kSpaceMd),
                        _ErrorBanner(
                          message: message,
                          problem: controller.problem.value,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              DmActionBar(
                child: DmWideButton(
                  key: const ValueKey('delete-account-confirm'),
                  label: controller.busy
                      ? 'Deleting…'
                      : controller.error.value != null
                      ? 'Try Again'
                      : 'Delete Account',
                  icon: Icons.delete_forever_outlined,
                  height: 52,
                  compact: true,
                  color: AppColors.error,
                  onTap: controller.canSubmit ? controller.deleteAccount : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatGoes extends GetView<DeleteAccountViewModel> {
  const _WhatGoes();

  @override
  Widget build(BuildContext context) {
    final email = controller.email;
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      radius: _radius,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What’s permanently deleted',
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 12),
          _Item(
            Icons.person_outline,
            email.isEmpty
                ? 'Your account and how you sign in'
                : 'Your account and how you sign in ($email)',
          ),
          const _Item(
            Icons.group_outlined,
            'Every profile you manage, yours and your family’s, with their '
            'medicines, schedules, dose history, appointments and photos',
          ),
          const _Item(
            Icons.link_off,
            'Access you gave other people to your profiles, and invitations '
            'you sent',
          ),
          const _Item(
            Icons.how_to_reg_outlined,
            'Your access to profiles other people shared with you. Their '
            'profiles and data stay with them',
          ),
          const _Item(
            Icons.notifications_off_outlined,
            'Reminders, alarms and alert registrations on your devices',
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 22, color: AppColors.error)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 22, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirming it's the account holder, and that they understand.
class _Confirm extends GetView<DeleteAccountViewModel> {
  const _Confirm();

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.labelLg.copyWith(
      color: AppColors.onSurface,
    );
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.usesPassword) ...[
            Text('Enter your password to confirm', style: labelStyle),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('delete-account-password'),
              controller: controller.password,
              obscureText: controller.obscurePassword.value,
              autofillHints: const [AutofillHints.password],
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => controller.deleteAccount(),
              style: AppTextStyles.bodyLg.copyWith(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Password',
                errorText: controller.passwordError.value,
                errorMaxLines: 3,
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                prefixIcon: Icon(Icons.lock_outline, color: AppColors.outline),
                suffixIcon: IconButton(
                  tooltip: controller.obscurePassword.value
                      ? 'Show password'
                      : 'Hide password',
                  onPressed: controller.obscurePassword.toggle,
                  icon: Icon(
                    controller.obscurePassword.value
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.outline),
                ),
              ),
            ),
          ] else
            Text(
              'You’ll be asked to confirm with the Google account you sign '
              'in with.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: kSpaceMd),
          MergeSemantics(
            child: Material(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('delete-account-understood'),
                borderRadius: BorderRadius.circular(16),
                onTap: controller.toggleUnderstood,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: controller.understood.value,
                        onChanged: (_) => controller.toggleUnderstood(),
                        activeColor: AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'I understand this permanently deletes my account '
                          'and everything in it.',
                          style: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Each step in turn: done, running or still to come.
class _Progress extends GetView<DeleteAccountViewModel> {
  const _Progress();

  static const _labels = {
    DeleteStep.confirming: 'Confirming it’s you',
    DeleteStep.syncing: 'Sending changes saved on this device',
    DeleteStep.deleting: 'Deleting your data, shares and account',
    DeleteStep.clearing: 'Clearing this device and signing out',
  };

  @override
  Widget build(BuildContext context) {
    final current = controller.step.value!;
    return Semantics(
      liveRegion: true,
      label: '${_labels[current]}. Keep the app open.',
      child: DmCard(
        color: AppColors.surfaceContainerLowest,
        radius: _radius,
        shadow: kShadowSm,
        padding: const EdgeInsets.all(20),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in DeleteStep.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: s.index < current.index
                            ? Icon(Icons.check_circle, color: AppColors.success)
                            : s == current
                            ? Padding(
                                padding: const EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.error,
                                ),
                              )
                            : Icon(
                                Icons.radio_button_unchecked,
                                color: AppColors.outline,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _labels[s]!,
                          style: AppTextStyles.bodyMd.copyWith(
                            color: s.index > current.index
                                ? AppColors.onSurfaceVariant
                                : AppColors.onSurface,
                            fontWeight: s == current
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Keep the app open. This can take a minute.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.problem});

  final String message;
  final DeletionProblem? problem;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(kSpaceMd),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.error_outline, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    switch (problem) {
                      DeletionProblem.incomplete => 'Not fully deleted',
                      DeletionProblem.recentLogin ||
                      DeletionProblem.unsynced ||
                      null => 'Account not deleted',
                      _ => 'Deletion didn’t finish',
                    },
                    style: AppTextStyles.labelLg.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
