import 'dart:async';

import 'package:dosemate/data/repositories/places_repository.dart';

/// Scriptable Places API: each search waits on its own completer so tests
/// can answer requests out of order.
class FakePlaces extends PlacesRepository {
  FakePlaces() : super(apiKey: 'test');

  final searches =
      <
        ({String input, String token, Completer<List<PlaceSuggestion>> reply})
      >[];
  final detailRequests = <({String placeId, String token})>[];
  PlacesFailure? detailsFailure;

  @override
  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
  }) {
    final reply = Completer<List<PlaceSuggestion>>();
    searches.add((input: input, token: sessionToken, reply: reply));
    return reply.future;
  }

  @override
  Future<PlaceDetails> details(
    String placeId, {
    required String sessionToken,
  }) async {
    detailRequests.add((placeId: placeId, token: sessionToken));
    if (detailsFailure case final e?) throw e;
    return const PlaceDetails(
      placeId: 'place-stjude',
      name: 'St. Jude Dental Clinic',
      address: '120 Medical Center Dr, Fullerton, CA 92835, USA',
      latitude: 33.8823,
      longitude: -117.9256,
    );
  }
}

const stJude = PlaceSuggestion(
  placeId: 'place-stjude',
  name: 'St. Jude Dental Clinic',
  address: '120 Medical Center Dr, Fullerton, CA, USA',
);
