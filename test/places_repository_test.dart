import 'dart:convert';

import 'package:dosemate/data/repositories/places_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'autocomplete sends the key, session token and a minimal field mask',
    () async {
      late http.Request sent;
      final repo = PlacesRepository(
        apiKey: 'k',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'suggestions': [
                {
                  'placePrediction': {
                    'placeId': 'abc',
                    'text': {'text': 'St. Jude, 120 Medical Center Dr'},
                    'structuredFormat': {
                      'mainText': {'text': 'St. Jude'},
                      'secondaryText': {'text': '120 Medical Center Dr'},
                    },
                  },
                },
                {
                  'queryPrediction': {
                    'text': {'text': 'ignored'},
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final results = await repo.autocomplete('st ju', sessionToken: 'tok');
      expect(
        sent.url.toString(),
        'https://places.googleapis.com/v1/places:autocomplete',
      );
      expect(sent.headers['X-Goog-Api-Key'], 'k');
      expect(sent.headers['X-Goog-FieldMask'], isNot(contains('*')));
      expect(jsonDecode(sent.body), {'input': 'st ju', 'sessionToken': 'tok'});
      expect(results.single.placeId, 'abc');
      expect(results.single.name, 'St. Jude');
      expect(results.single.address, '120 Medical Center Dr');
    },
  );

  test('details requests only id, name, address and location', () async {
    late http.Request sent;
    final repo = PlacesRepository(
      apiKey: 'k',
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'id': 'abc',
            'displayName': {'text': 'St. Jude'},
            'formattedAddress': '120 Medical Center Dr, Fullerton, CA, USA',
            'location': {'latitude': 33.88, 'longitude': -117.92},
          }),
          200,
        );
      }),
    );
    final place = await repo.details('abc', sessionToken: 'tok');
    expect(sent.url.path, '/v1/places/abc');
    expect(sent.url.queryParameters['sessionToken'], 'tok');
    expect(
      sent.headers['X-Goog-FieldMask'],
      'id,displayName,formattedAddress,location',
    );
    expect(place.latitude, 33.88);
    expect(place.longitude, -117.92);
    expect(place.address, '120 Medical Center Dr, Fullerton, CA, USA');
  });

  test('API, network and setup errors become readable failures', () async {
    Future<PlacesFailure> failure(PlacesRepository repo) async {
      try {
        await repo.autocomplete('clinic', sessionToken: 't');
      } on PlacesFailure catch (e) {
        return e;
      }
      fail('expected a failure');
    }

    final denied = await failure(
      PlacesRepository(
        apiKey: 'k',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'status': 'PERMISSION_DENIED'},
            }),
            403,
          ),
        ),
      ),
    );
    expect(denied.code, 'PERMISSION_DENIED');
    expect(denied.message, isNot(contains('k')));

    final offline = await failure(
      PlacesRepository(
        apiKey: 'k',
        client: MockClient((_) async => throw http.ClientException('down')),
      ),
    );
    expect(offline.code, 'network');

    final noKey = await failure(PlacesRepository(apiKey: ''));
    expect(noKey.code, 'no-key');
  });

  test('session tokens are fresh version 4 UUIDs', () {
    final a = PlacesRepository.newSessionToken();
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(PlacesRepository.newSessionToken(), isNot(a));
  });
}
