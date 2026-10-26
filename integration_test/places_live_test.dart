// Address search against the live Places API (New), on a device, through
// the real visit form; visits are saved to an in-memory store. Needs the
// platform's restricted key:
//   flutter test integration_test/places_live_test.dart -d <device> \
//     --dart-define-from-file=config/keys.json
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/places_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/add_visit/view_model/add_visit_view_model.dart';
import 'package:dosemate/modules/add_visit/views/add_visit_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_care.dart';
import '../test/support/fake_profiles.dart';
import '../test/support/shell_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const uid = 'uid-1';

  testWidgets('live search: suggestions as you type, selection, save and '
      'reopen keep the place', (tester) async {
    final places = PlacesRepository();
    expect(places.isConfigured, isTrue, reason: 'run with config/keys.json');

    // Straight to the API first: what the form will get.
    final token = PlacesRepository.newSessionToken();
    final direct = await places.autocomplete(
      'Shaukat Khanum Hospital Lahore',
      sessionToken: token,
    );
    debugPrint('direct suggestions: ${direct.length}');
    expect(direct, isNotEmpty);

    Get.testMode = true;
    final profiles = ProfileService(
      FakeProfiles()..put(
        uid,
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Live Test',
        ),
      ),
    );
    await profiles.start(uid, selfName: 'Live Test');
    Get.put(AuthService(AuthRepository(NoAuth()), profiles)).user.value =
        FakeUser();
    final store = FakeCare();
    putCare(profiles, store, now: fixedNow);
    Get.put<PlacesRepository>(places);
    final vm = Get.put(AddVisitViewModel());
    // Opened over another screen, as in the app, so saving can go back.
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: Text('Home'))),
    );
    Get.to<void>(() => const AddVisitView());
    await tester.pumpAndSettle();

    final address = find.byWidgetPredicate(
      (w) => w is TextField && w.controller == vm.address,
    );
    await tester.ensureVisible(address);
    // Typed a character at a time: only the settled text is searched.
    var typed = '';
    for (final c in 'Shaukat Khanum Hospital'.split('')) {
      typed += c;
      await tester.enterText(address, typed);
      await tester.pump(const Duration(milliseconds: 60));
    }
    Future<void> waitFor(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await waitFor(() => vm.placeSearch.value == PlaceSearch.results);
    debugPrint(
      'form state ${vm.placeSearch.value}, error ${vm.placeError.value}',
    );
    expect(vm.placeSearch.value, PlaceSearch.results);
    expect(vm.suggestions, isNotEmpty);
    final first = vm.suggestions.first;
    debugPrint('first suggestion: ${first.name} | ${first.address}');
    expect(find.text('Powered by Google'), findsOneWidget);

    await tester.tap(find.text(first.name).first);
    await waitFor(() => vm.selectedPlace.value != null);
    final place = vm.selectedPlace.value!;
    debugPrint(
      'selected: ${place.name} | ${vm.address.text} | '
      '${place.latitude}, ${place.longitude}',
    );
    expect(place.placeId, isNotEmpty);
    expect(place.latitude, inInclusiveRange(-90, 90));
    expect(place.longitude, inInclusiveRange(-180, 180));
    expect(vm.address.text, isNotEmpty);

    vm.title.text = 'Live search check';
    vm.setDate(DateTime(2026, 10, 25));
    await vm.save();
    await tester.pumpAndSettle();
    final saved = store.visitsOf(uid, 'self').values.single;
    expect(saved.place?.placeId, place.placeId);
    expect(saved.place?.latitude, place.latitude);
    expect(saved.address, vm.address.text);

    // Reopened for editing: the same place, coordinates and address.
    Get.delete<AddVisitViewModel>();
    final edit = Get.put(AddVisitViewModel(editing: saved));
    expect(edit.selectedPlace.value?.placeId, place.placeId);
    expect(edit.selectedPlace.value?.longitude, place.longitude);
    expect(edit.address.text, saved.address);
    debugPrint('saved and reopened with the same place');
    // The "Visit saved" snackbar animates on timers; let it finish.
    for (var i = 0; i < 3; i++) {
      Get.closeAllSnackbars();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    Get.reset();
  });
}
