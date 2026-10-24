import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

/// A user-facing Places error. [message] is safe to show in the UI.
class PlacesFailure implements Exception {
  const PlacesFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'PlacesFailure($code): $message';
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
  PlacesRepository({
    http.Client? client,
    this.apiKey = AppConfig.googleMapsApiKey,
  }) : _client = client ?? http.Client();

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
        'Address search isn’t set up. You can still type the address.',
        code: 'no-key',
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
        'Address search is taking too long. Check your connection.',
        code: 'timeout',
      );
    } on Exception {
      throw const PlacesFailure(
        "You're offline. You can still type the address.",
        code: 'network',
      );
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on Object {
      body = const {};
    }
    if (response.statusCode == 200) return body;
    final status = (body['error'] as Map?)?['status'] as String?;
    // Status codes only; never the key or the user's input.
    if (kDebugMode) debugPrint('Places error ${response.statusCode} $status');
    throw PlacesFailure(switch (response.statusCode) {
      403 || 401 => 'Address search isn’t available right now.',
      429 => 'Too many searches. Wait a moment and try again.',
      _ => 'Address search failed. Try again or type the address.',
    }, code: status ?? '${response.statusCode}');
  }

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
