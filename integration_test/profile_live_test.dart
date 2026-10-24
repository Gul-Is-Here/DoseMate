// End-to-end check against the live Firebase project. Run through
// tool-style harness that creates a throwaway account, seeds a legacy
// (pre-profiles) document for it, and deletes everything afterwards:
//   flutter test integration_test/profile_live_test.dart -d <device> \
//     --dart-define=PROBE_EMAIL=... --dart-define=PROBE_PASSWORD=...
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// 1x1 PNG.
const _png = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live migration, profiles, switching and isolation', (
    tester,
  ) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instance;
    await auth.signInWithEmailAndPassword(
      email: const String.fromEnvironment('PROBE_EMAIL'),
      password: const String.fromEnvironment('PROBE_PASSWORD'),
    );
    final uid = auth.currentUser!.uid;
    final repo = ProfileRepository(
      FirebaseFirestore.instance,
      FirebaseStorage.instance,
    );
    final uploaded = <String>[];

    try {
      // 1. Migration of the seeded legacy caregiver profile.
      final service = ProfileService(repo);
      await service.start(uid, selfName: 'Probe Self');
      expect(service.isReady, isTrue, reason: service.error.value);
      final migrated = service.byId(ProfileRepository.migratedProfileId)!;
      expect(migrated.type, ProfileType.parent);
      expect(migrated.fullName, 'Ruth Legacy');
      expect(migrated.emergencyContactName, 'Legacy Contact');
      expect(migrated.photoPath, 'users/$uid/profile/legacy.jpg');
      expect(service.selfProfile!.fullName, 'Probe Self');
      expect(service.account.value.setupCompleted, isTrue);
      expect(service.activeProfile!.isSelf, isTrue);
      debugPrint('PROBE migrated legacy caregiver -> Parent + Myself');

      // 2. Migration is idempotent.
      await service.start(uid, selfName: 'Probe Self', force: true);
      expect(service.profiles, hasLength(2));
      debugPrint('PROBE second migration run: no duplicates');

      // 3. Create a Spouse profile with its own photo.
      final spouseId = service.newProfileId();
      final file = File('${Directory.systemTemp.path}/probe.png')
        ..writeAsBytesSync(_png);
      await service.save(
        UserProfile(
          id: spouseId,
          type: ProfileType.spouse,
          fullName: 'Sam Probe',
        ),
        newPhoto: file,
      );
      final spouse = service.byId(spouseId)!;
      uploaded.add(spouse.photoPath!);
      expect(spouse.photoPath, startsWith('users/$uid/profiles/$spouseId/'));
      debugPrint('PROBE created Spouse with its own photo');

      // 4. Editing Myself leaves the others untouched.
      await service.save(
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Probe Self Edited',
        ),
      );
      final fresh = ProfileService(repo);
      await fresh.start(uid, selfName: 'Probe Self');
      expect(fresh.selfProfile!.fullName, 'Probe Self Edited');
      expect(fresh.byId(spouseId)!.fullName, 'Sam Probe');
      expect(
        fresh.byId(ProfileRepository.migratedProfileId)!.fullName,
        'Ruth Legacy',
      );
      fresh.stop();
      debugPrint('PROBE edited Myself; Spouse and Parent unchanged');

      // 5. Switch, then "restart" and restore.
      await service.switchTo(spouseId);
      service.stop();
      final restarted = ProfileService(repo);
      await restarted.start(uid, selfName: 'Probe Self');
      expect(restarted.activeProfile!.id, spouseId);
      restarted.stop();
      debugPrint('PROBE active profile restored after restart');

      // 6. Another account's profiles are off limits.
      try {
        await FirebaseFirestore.instance
            .collection('users/someone-else/profiles')
            .get();
        fail('read another account');
      } on FirebaseException catch (e) {
        expect(e.code, 'permission-denied');
      }
      try {
        await FirebaseFirestore.instance
            .doc('users/someone-else/profiles/self')
            .set({
              'type': 'self',
              'fullName': 'x',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
        fail('wrote another account');
      } on FirebaseException catch (e) {
        expect(e.code, 'permission-denied');
      }
      try {
        await FirebaseStorage.instance
            .ref('users/someone-else/profiles/self/x.png')
            .putData(
              Uint8List.fromList(_png),
              SettableMetadata(contentType: 'image/png'),
            );
        fail('uploaded into another account');
      } on FirebaseException catch (e) {
        expect(e.code, 'unauthorized');
      }
      debugPrint('PROBE other accounts denied (read, write, upload)');
    } finally {
      for (final path in uploaded) {
        await repo.deletePhoto(path);
      }
      await auth.signOut();
      debugPrint('PROBE done');
    }
  });
}
