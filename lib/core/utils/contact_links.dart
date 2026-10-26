import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_snackbar.dart';

/// Opens the phone dialer for [number]; tells the user when it can't.
Future<void> callNumber(String number) async {
  final digits = number.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.length < 3) {
    showSnack('No phone number', 'Add a phone number for this visit first.');
    return;
  }
  await _open(Uri(scheme: 'tel', path: digits), "Couldn't start a call");
}

/// Opens directions to [address] in the device's maps app or browser.
Future<void> openDirections(String address) async {
  final query = address.trim();
  if (query.isEmpty) {
    showSnack('No address', 'Add the clinic address for this visit first.');
    return;
  }
  await _open(
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}),
    "Couldn't open directions",
  );
}

/// Opens a web page (e.g. the privacy policy) in an in-app browser tab.
Future<void> openWebPage(Uri uri) =>
    _open(uri, "Couldn't open the page", mode: LaunchMode.inAppBrowserView);

Future<void> _open(
  Uri uri,
  String failure, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: mode);
  } on Exception {
    opened = false;
  }
  if (!opened) showSnack(failure, 'No app on this device can open it.');
}
