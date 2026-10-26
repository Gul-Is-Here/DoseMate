import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../widgets/app_snackbar.dart';

/// Where a deletion is; null while nothing runs.
enum DeleteStep { confirming, syncing, deleting, clearing }

/// Delete Account: confirm it's you (password or Google), send this
/// device's queued changes, have the server delete everything, then clear
/// this device and sign out. Success is only reported once the server says
/// every record, file and share is gone and the Auth user deleted.
class DeleteAccountViewModel extends GetxController {
  DeleteAccountViewModel({AuthService? auth, AccountRepository? accounts})
    : _auth = auth ?? Get.find<AuthService>(),
      _accounts = accounts ?? Get.find<AccountRepository>();

  final AuthService _auth;
  final AccountRepository _accounts;

  AuthRepository get _repo => _auth.repository;

  final password = TextEditingController();
  final hasPassword = false.obs;
  final obscurePassword = true.obs;
  final understood = false.obs;

  final step = Rxn<DeleteStep>();
  final passwordError = RxnString();
  final error = RxnString();

  /// The last failure, for what the screen offers next.
  final problem = Rxn<DeletionProblem>();

  /// Data sync is stopped while the server deletes; restarted when the
  /// account certainly still exists, or when the screen closes.
  bool _paused = false;

  /// Password accounts confirm with their password; Google ones with Google.
  bool get usesPassword => _repo.hasPassword;

  String get email => _auth.user.value?.email ?? '';

  bool get busy => step.value != null;

  bool get canSubmit =>
      !busy && understood.value && (!usesPassword || hasPassword.value);

  @override
  void onInit() {
    super.onInit();
    password.addListener(() => hasPassword.value = password.text.isNotEmpty);
  }

  void toggleUnderstood() {
    if (!busy) understood.toggle();
  }

  Future<void> deleteAccount() async {
    if (!canSubmit) return;
    error.value = passwordError.value = problem.value = null;

    step.value = DeleteStep.confirming;
    try {
      if (usesPassword) {
        await _repo.reauthenticateWithPassword(password.text);
      } else {
        await _repo.reauthenticateWithGoogle();
      }
    } on AuthCancelled {
      step.value = null;
      return;
    } on AuthFailure catch (e) {
      step.value = null;
      // Gone already (an earlier attempt finished after its answer was
      // lost): only this device is left to clear.
      if (e.code == 'user-not-found') return _finish();
      if (usesPassword && _passwordCodes.contains(e.code)) {
        passwordError.value = e.message;
      } else {
        error.value = e.message;
      }
      return;
    }

    step.value = DeleteStep.syncing;
    try {
      await _accounts.flushPendingWrites();
    } on AccountDeletionFailure catch (e) {
      return _fail(e);
    }

    step.value = DeleteStep.deleting;
    _auth.pauseAccountSync();
    _paused = true;
    try {
      await _accounts.deleteAccount();
    } on AccountDeletionFailure catch (e) {
      // Only a refused request certainly left the account as it was.
      if (e.problem == DeletionProblem.recentLogin) await _resume();
      return _fail(e);
    } catch (e) {
      if (kDebugMode) debugPrint('Delete account error: ${e.runtimeType}');
      return _fail(
        const AccountDeletionFailure(
          DeletionProblem.unknown,
          'Your account couldn’t be deleted. Try again.',
        ),
      );
    }
    _paused = false;
    await _finish();
  }

  static const _passwordCodes = {
    'wrong-password',
    'invalid-credential',
    'INVALID_LOGIN_CREDENTIALS',
    'too-many-requests',
  };

  void _fail(AccountDeletionFailure e) {
    if (isClosed) return;
    step.value = null;
    problem.value = e.problem;
    error.value = e.message;
    if (e.problem == DeletionProblem.recentLogin) password.clear();
  }

  Future<void> _resume() async {
    if (!_paused) return;
    _paused = false;
    await _auth.resumeAccountSync();
  }

  Future<void> _finish() async {
    step.value = DeleteStep.clearing;
    // Signing out opens sign in, which closes this screen.
    await _auth.finishAccountDeletion();
    showSnack(
      'Account deleted',
      'Your DoseMate account and its data were permanently deleted.',
    );
  }

  @override
  void onClose() {
    // Left without finishing: the account is still there, so its data
    // follows again.
    if (_paused) _resume();
    password.dispose();
    super.onClose();
  }
}
