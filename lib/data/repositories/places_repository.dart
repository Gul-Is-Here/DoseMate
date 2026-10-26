import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

/// Why a Places request failed, for what the UI offers next.
enum PlacesErrorKind {
  /// No connection, or no answer in time. Worth retrying.
  network,

  /// The key was rejected: invalid, or not allowed for this app build.
  auth,

  /// Too many requests for now. Worth retrying a little later.
  quota,

  /// Not set up: no key in this build, the API or billing turned off, or
  /// the key not allowed to use Places API (New).
  config,

  /// Google's side failed or the reply was unusable. Worth retrying.
  server,

  /// The chosen place can't be used (it has no map location).
  unusable,
}

/// A user-facing Places error. [message] is safe to show in the UI.
class PlacesFailure implements Exception {
  const PlacesFailure(
    this.message, {
    this.code,
    this.kind = PlacesErrorKind.server,
  });

  final String message;

  /// The API's status or reason code, for logs and tests; never shown.
  final String? code;
  final PlacesErrorKind kind;

  /// Repeating the same request may succeed. Setup and key problems need
  /// a fix outside the app, so a retry would only fail again.
  bool get retryable => switch (kind) {
    PlacesErrorKind.network ||
    PlacesErrorKind.quota ||
    PlacesErrorKind.server => true,
    PlacesErrorKind.auth ||
    PlacesErrorKind.config ||
    PlacesErrorKind.unusable => false,
  };

  @override
  String toString() => 'PlacesFailure(${kind.name}, $code): $message';
}

/// One autocomplete suggestion.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.name,
    required this.address,
  });

  final String placeId;

  /// "St. Jude Dental Clinic".
  final String name;

  /// "120 Medical Center Dr, Fullerton, CA, USA".
  final String address;
}

/// A chosen place with its coordinates.
class PlaceDetails {
  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
}

/// Places API (New) over HTTPS. One session token covers a run of
/// autocomplete requests and the details request that ends it, so the
/// session is billed once.
class PlacesRepository {
  PlacesRepository({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      apiKey = apiKey ?? AppConfig.placesApiKey;

  final http.Client _client;
  final String apiKey;

  static const _host = 'places.googleapis.com';
  static const timeout = Duration(seconds: 10);

  bool get isConfigured => apiKey.isNotEmpty;

  /// A new random (version 4) UUID for an autocomplete session.
  static String newSessionToken() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) async {
    final data = await _send(
      http.Request('POST', Uri.https(_host, '/v1/places:autocomplete'))
        ..headers.addAll({
          'Content-Type': 'application/json',
          // Only what the suggestion list shows.
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.text.text,'
              'suggestions.placePrediction.structuredFormat',
        })
        ..body = jsonEncode({'input': input, 'sessionToken': sessionToken}),
    );
    return [
      for (final s in data['suggestions'] as List? ?? const [])
        if ((s as Map)['placePrediction'] case final Map p
            when p['placeId'] is String)
          PlaceSuggestion(
            placeId: p['placeId'] as String,
            name:
                _text(p['structuredFormat']?['mainText']) ??
                _text(p['text']) ??
                '',
            address:
                _text(p['structuredFormat']?['secondaryText']) ??
                _text(p['text']) ??
                '',
          ),
    ];
  }

  /// Ends the session. Requests only the fields stored with a visit.
  Future<PlaceDetails> details(
    String placeId, {
    required String sessionToken,
  }) async {
    final data = await _send(
      http.Request(
          'GET',
          Uri.https(_host, '/v1/places/${Uri.encodeComponent(placeId)}', {
            'sessionToken': sessionToken,
          }),
        )
        ..headers['X-Goog-FieldMask'] =
            'id,displayName,formattedAddress,location',
    );
    final location = data['location'];
    final lat = location is Map ? location['latitude'] : null;
    final lng = location is Map ? location['longitude'] : null;
    if (lat is! num || lng is! num) {
      throw const PlacesFailure(
        'That place has no map location. Choose another suggestion.',
        code: 'no-location',
        kind: PlacesErrorKind.unusable,
      );
    }
    final address = data['formattedAddress'] as String? ?? '';
    return PlaceDetails(
      placeId: data['id'] as String? ?? placeId,
      name: _text(data['displayName']) ?? address,
      address: address,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }

  static String? _text(Object? value) =>
      value is Map && value['text'] is String ? value['text'] as String : null;

  Future<Map<String, dynamic>> _send(http.Request request) async {
    if (!isConfigured) {
      throw const PlacesFailure(
        'Address search isn’t set up in this version of the app. You can '
        'still type the address.',
        code: 'no-key',
        kind: PlacesErrorKind.config,
      );
    }
    request.headers.addAll({'X-Goog-Api-Key': apiKey, ..._appHeaders()});
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const PlacesFailure(
        'Address search is taking too long. Check your connection and try '
        'again.',
        code: 'timeout',
        kind: PlacesErrorKind.network,
      );
    } on Exception {
      throw const PlacesFailure(
        "You're offline. Check your connection and try again, or type the "
        'address.',
        code: 'network',
        kind: PlacesErrorKind.network,
      );
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      body = const {};
    }
    if (response.statusCode == 200) return body;
    final error = body['error'] is Map ? body['error'] as Map : const {};
    final status = error['status'] is String ? error['status'] as String : null;
    final reason = _reason(error);
    // Codes only; never the key, the message or the user's input.
    if (kDebugMode) {
      debugPrint('Places error ${response.statusCode} $status $reason');
    }
    final kind = classify(response.statusCode, status, reason);
    throw PlacesFailure(
      _messages[kind]!,
      code: reason ?? status ?? '${response.statusCode}',
      kind: kind,
    );
  }

  /// The ErrorInfo reason, e.g. SERVICE_DISABLED or API_KEY_INVALID.
  static String? _reason(Map error) {
    for (final d in error['details'] as List? ?? const []) {
      if (d is Map && d['reason'] is String) return d['reason'] as String;
    }
    return null;
  }

  /// Sorts an error reply by what fixes it.
  @visibleForTesting
  static PlacesErrorKind classify(
    int statusCode,
    String? status,
    String? reason,
  ) {
    switch (reason) {
      case 'SERVICE_DISABLED' ||
          'API_KEY_SERVICE_BLOCKED' ||
          'BILLING_DISABLED' ||
          'CONSUMER_INVALID' ||
          'ACCESS_TOKEN_SCOPE_INSUFFICIENT':
        return PlacesErrorKind.config;
      case 'API_KEY_INVALID' ||
          'API_KEY_EXPIRED' ||
          'API_KEY_ANDROID_APP_BLOCKED' ||
          'API_KEY_IOS_APP_BLOCKED' ||
          'API_KEY_HTTP_REFERRER_BLOCKED' ||
          'API_KEY_IP_ADDRESS_BLOCKED':
        return PlacesErrorKind.auth;
      case 'RATE_LIMIT_EXCEEDED' || 'RESOURCE_EXHAUSTED':
        return PlacesErrorKind.quota;
    }
    if (statusCode == 429 || status == 'RESOURCE_EXHAUSTED') {
      return PlacesErrorKind.quota;
    }
    if (statusCode == 401 || status == 'UNAUTHENTICATED') {
      return PlacesErrorKind.auth;
    }
    // An invalid key comes back as 400 INVALID_ARGUMENT.
    if (statusCode == 403 || status == 'PERMISSION_DENIED') {
      return PlacesErrorKind.config;
    }
    return PlacesErrorKind.server;
  }

  static const _messages = {
    PlacesErrorKind.network:
        "You're offline. Check your connection and try "
        'again, or type the address.',
    PlacesErrorKind.auth:
        'This version of the app isn’t allowed to use '
        'address search. You can still type the address.',
    PlacesErrorKind.quota:
        'Too many address searches right now. Wait a '
        'moment and try again.',
    PlacesErrorKind.config:
        'Address search isn’t set up yet. You can still '
        'type the address.',
    PlacesErrorKind.server:
        'Address search had a problem. Try again, or type '
        'the address.',
    PlacesErrorKind.unusable:
        'That place can’t be used. Choose another '
        'suggestion.',
  };

  /// Identify the app so a key with Android/iOS app restrictions accepts
  /// these REST calls.
  static Map<String, String> _appHeaders() {
    if (kIsWeb) return const {};
    if (Platform.isAndroid && AppConfig.androidCertSha1.isNotEmpty) {
      return {
        'X-Android-Package': AppConfig.appId,
        'X-Android-Cert': AppConfig.androidCertSha1,
      };
    }
    if (Platform.isIOS) return {'X-Ios-Bundle-Identifier': AppConfig.appId};
    return const {};
  }
}
