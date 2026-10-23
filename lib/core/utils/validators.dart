/// Form validators. Each returns an error message, or null when valid.
abstract class Validators {
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static const minPasswordLength = 8;

  static String? name(String value) =>
      value.trim().isEmpty ? 'Enter your full name.' : null;

  static String? email(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  /// Only checks presence; sign-in must not reveal password rules.
  static String? loginPassword(String value) =>
      value.isEmpty ? 'Enter your password.' : null;

  static String? newPassword(String value) {
    if (value.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    if (!value.contains(RegExp(r'[A-Za-z]')) ||
        !value.contains(RegExp(r'\d'))) {
      return 'Use both letters and numbers.';
    }
    return null;
  }

  static String? confirmPassword(String password, String confirm) {
    if (confirm.isEmpty) return 'Confirm your password.';
    if (password != confirm) return 'Passwords do not match.';
    return null;
  }
}
