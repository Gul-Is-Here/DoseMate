import 'dart:io';

import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_profiles.dart';

void main() {
  const uid = 'uid-1';
  late FakeProfiles store;
  late ProfileService service;

  UserProfile profile(
    String id,
    ProfileType type,
    String name, {
    String? relationship,
  }) => UserProfile(
    id: id,
    type: type,
    fullName: name,
    relationship: relationship,
  );

  Future<void> start() => service.start(uid, selfName: 'Eleanor Vance');

  setUp(() {
    store = FakeProfiles();
    service = ProfileService(store);
  });

  test('start migrates, loads and lists Myself first', () async {
    store
      ..put(uid, profile('p1', ProfileType.parent, 'Ruth'))
      ..put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'));
    await start();
    expect(store.migrations, [uid]);
    expect(service.isReady, isTrue);
    expect(service.profiles.map((p) => p.id), [UserProfile.selfId, 'p1']);
    expect(service.activeProfile!.isSelf, isTrue);
  });

  test(
    'creating profiles gives each its own id and leaves others alone',
    () async {
      store.put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'));
      await start();
      await service.save(
        profile(
          'p1',
          ProfileType.parent,
          'Ruth',
          relationship: 'Mother / Senior Parent',
        ),
      );
      await service.save(profile('p2', ProfileType.spouse, 'Sam'));
      expect(
        store.profilesOf(uid).keys,
        containsAll([UserProfile.selfId, 'p1', 'p2']),
      );
      expect(store.profilesOf(uid)[UserProfile.selfId]!.fullName, 'Eleanor');
      expect(service.byId('p2')!.fullName, 'Sam');
    },
  );

  test('editing one profile never changes another', () async {
    store
      ..put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'))
      ..put(uid, profile('p1', ProfileType.parent, 'Ruth'));
    await start();
    await service.switchTo('p1');
    await service.save(
      profile(UserProfile.selfId, ProfileType.self, 'Eleanor V.'),
    );
    expect(store.profilesOf(uid)['p1']!.fullName, 'Ruth');
    expect(store.profilesOf(uid)[UserProfile.selfId]!.fullName, 'Eleanor V.');
    expect(service.activeProfile!.id, 'p1', reason: 'saving does not switch');
  });

  test(
    'photos are stored per profile and replaced only after a successful save',
    () async {
      store.put(uid, profile('p1', ProfileType.parent, 'Ruth'));
      await start();
      await service.save(
        profile('p1', ProfileType.parent, 'Ruth'),
        newPhoto: File('a.jpg'),
      );
      await service.save(
        profile('p1', ProfileType.parent, 'Ruth'),
        newPhoto: File('b.jpg'),
      );
      expect(
        store.profilesOf(uid)['p1']!.photoPath,
        'users/uid-1/profiles/p1/avatar_2.jpg',
      );
      expect(store.deleted, ['users/uid-1/profiles/p1/avatar_1.jpg']);

      store.saveFailure = const ProfileFailure('offline');
      await expectLater(
        service.save(
          profile('p1', ProfileType.parent, 'Ruth'),
          newPhoto: File('c.jpg'),
        ),
        throwsA(isA<ProfileFailure>()),
      );
      expect(
        service.byId('p1')!.photoPath,
        'users/uid-1/profiles/p1/avatar_2.jpg',
      );
      expect(store.deleted.last, 'users/uid-1/profiles/p1/avatar_3.jpg');
    },
  );

  test(
    'the active profile is remembered and restored after a restart',
    () async {
      store
        ..put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'))
        ..put(uid, profile('p1', ProfileType.parent, 'Ruth'));
      await start();
      await service.switchTo('p1');
      expect(service.activeProfile!.fullName, 'Ruth');

      final afterRestart = ProfileService(store);
      await afterRestart.start(uid, selfName: 'Eleanor Vance');
      expect(afterRestart.activeProfile!.id, 'p1');
    },
  );

  test('an unavailable active profile falls back to Myself', () async {
    store
      ..put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'))
      ..accounts[uid] = const AccountState(activeProfileId: 'gone');
    await start();
    expect(service.activeProfile!.isSelf, isTrue);
  });

  test('switching to an unknown profile is ignored', () async {
    store.put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'));
    await start();
    await service.switchTo('not-mine');
    expect(service.activeProfileId.value, UserProfile.selfId);
  });

  test('a load failure is reported and can be retried', () async {
    store.readFailure = const ProfileFailure("You're offline.");
    await start();
    expect(service.status.value, ProfilesStatus.error);
    expect(service.error.value, "You're offline.");

    store.readFailure = null;
    await service.retry();
    expect(service.isReady, isTrue);
  });

  test('stop cancels the listener and clears every profile', () async {
    store.put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'));
    await start();
    expect(store.listeners(uid), 1);
    service.stop();
    expect(store.listeners(uid), 0);
    expect(service.profiles, isEmpty);
    expect(service.activeProfileId.value, UserProfile.selfId);
  });

  test("another account's data never appears after switching users", () async {
    store
      ..put(uid, profile(UserProfile.selfId, ProfileType.self, 'Eleanor'))
      ..put('uid-2', profile(UserProfile.selfId, ProfileType.self, 'Bob'));
    await start();
    await service.start('uid-2', selfName: 'Bob');
    expect(store.listeners(uid), 0, reason: 'old listener cancelled');
    expect(service.profiles.single.fullName, 'Bob');

    // A late update to the first account must not leak in.
    store.put(uid, profile('p9', ProfileType.other, 'Leak'));
    await Future<void>.delayed(Duration.zero);
    expect(service.profiles.map((p) => p.fullName), ['Bob']);
  });

  test(
    'saving during setup creates Myself when caring for someone else',
    () async {
      await start();
      await service.save(
        profile('p1', ProfileType.parent, 'Ruth'),
        markSetupComplete: true,
      );
      expect(
        store.profilesOf(uid)[UserProfile.selfId]!.fullName,
        'Eleanor Vance',
      );
      expect(service.account.value.setupCompleted, isTrue);
    },
  );

  test('legacy loved-one relationships map to profile types', () {
    expect(
      ProfileType.fromRelationship('Mother / Senior Parent'),
      ProfileType.parent,
    );
    expect(
      ProfileType.fromRelationship('Spouse or Partner'),
      ProfileType.spouse,
    );
    expect(ProfileType.fromRelationship('Home Care Client'), ProfileType.other);
    expect(ProfileType.fromRelationship(null), ProfileType.other);
  });

  test('a self profile never writes a relationship', () {
    final map = const UserProfile(
      id: UserProfile.selfId,
      type: ProfileType.self,
      fullName: 'E',
      relationship: 'Grandparent',
    ).toWriteMap();
    expect(map['relationship'], isNot('Grandparent'));
    expect(map['type'], 'self');
    expect(map.containsKey('createdAt'), isFalse);
  });
}
