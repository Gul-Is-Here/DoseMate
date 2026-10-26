import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Why deleting the account didn't finish.
enum DeletionProblem {
  /// The server wants a fresher sign in: confirm it's you again.
  recentLogin,

  /// Another deletion of this account is still running.
  inProgress,

  /// Some data was removed, some wasn't. Trying again finishes it.
  incomplete,

  /// Changes made on this device haven't reached the server yet.
  unsynced,

  /// The request didn't get through, or its answer didn't come back.
  network,

  /// It took too long to hear back; it may still be finishing.
  timeout,

  unknown,
}

/// A user-facing deletion error. [message] is safe to show in the UI.
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.problem, this.message);

  final DeletionProblem problem;
  final String message;

  @override
  String toString() => 'AccountDeletionFailure(${problem.name})';
}

/// Account deletion runs on the server (`deleteAccount` Cloud Function),
/// which removes every record, file, share and device of the account, then
/// the Firebase Auth user. It resolves only once all of that is done.
class AccountRepository {
  AccountRepository(this._firestore, {this.functions});

  final FirebaseFirestore _firestore;

  /// Null uses the default app's (resolved on first use).
  final FirebaseFunctions? functions;

  static const callTimeout = Duration(seconds: 310);
  static const syncTimeout = Duration(seconds: 15);

  /// Sends this device's queued writes first, so none of them lands after
  /// the deletion and leaves data behind.
  Future<void> flushPendingWrites() async {
    try {
      await _firestore.waitForPendingWrites().timeout(syncTimeout);
    } on TimeoutException {
      throw const AccountDeletionFailure(
        DeletionProblem.unsynced,
        'Some changes on this device haven’t synced yet. Connect to the '
        'internet and try again. Nothing was deleted.',
      );
    }
  }

  Future<void> deleteAccount() async {
    try {
      await (functions ?? FirebaseFunctions.instance)
          .httpsCallable(
            'deleteAccount',
            options: HttpsCallableOptions(timeout: callTimeout),
          )
          .call<Object?>();
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('Delete account error: ${e.code}');
      throw failureFor(e.code, e.details, e.message);
    }
  }

  /// Maps the function's error to what the screen offers next.
  @visibleForTesting
  static AccountDeletionFailure failureFor(
    String code,
    Object? details,
    String? message,
  ) {
    final reason = details is Map ? details['reason'] : null;
    if (reason == 'requires-recent-login') {
      return const AccountDeletionFailure(
        DeletionProblem.recentLogin,
        'For your security, confirm it’s you again. Nothing was deleted.',
      );
    }
    if (reason == 'in-progress') {
      return const AccountDeletionFailure(
        DeletionProblem.inProgress,
        'Your account is already being deleted. Wait a minute, then try '
        'again.',
      );
    }
    if (reason == 'incomplete') {
      return const AccountDeletionFailure(
        DeletionProblem.incomplete,
        'Your account wasn’t fully deleted. Some of your data may already '
        'be removed. Try again to finish.',
      );
    }
    return switch (code) {
      'unavailable' => const AccountDeletionFailure(
        DeletionProblem.network,
        'Couldn’t reach DoseMate. Check your connection and try again.',
      ),
      'deadline-exceeded' => const AccountDeletionFailure(
        DeletionProblem.timeout,
        'This is taking longer than expected, and may still be finishing. '
        'Wait a minute, then try again.',
      ),
      'unauthenticated' => const AccountDeletionFailure(
        DeletionProblem.recentLogin,
        'You were signed out. Confirm it’s you and try again.',
      ),
      _ => const AccountDeletionFailure(
        DeletionProblem.unknown,
        'Your account couldn’t be deleted. Try again.',
      ),
    };
  }
}
