import 'dart:async';

import 'package:dosemate/app/routes/app_routes.dart';
import 'package:dosemate/core/theme/app_text_styles.dart';
import 'package:dosemate/core/theme/app_theme.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/calendar_service.dart';
import 'package:dosemate/data/services/history_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:dosemate/modules/family/bindings/family_binding.dart';
import 'package:dosemate/modules/family/views/family_view.dart';
import 'package:dosemate/modules/medicine_details/bindings/medicine_details_binding.dart';
import 'package:dosemate/modules/medicine_details/view_model/medicine_details_view_model.dart';
import 'package:dosemate/modules/medicine_details/views/medicine_details_view.dart';
import 'package:dosemate/modules/notifications/bindings/notifications_binding.dart';
import 'package:dosemate/modules/notifications/views/notifications_view.dart';
import 'package:dosemate/modules/shell/bindings/shell_binding.dart';
import 'package:dosemate/modules/shell/views/main_shell_view.dart';
import 'package:dosemate/widgets/app_shell.dart';
import 'package:dosemate/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

/// Frame callbacks waiting to run: animations that are still ticking.
int get _ticking => SchedulerBinding.instance.transientCallbackCount;

Finder get _skeleton => find.byType(Skeleton);
Finder get _spinner => find.byType(CircularProgressIndicator);

/// The painted shape inside the first [Bone] under [of].
RenderObject _bone(WidgetTester tester, [Finder? of]) => tester.renderObject(
  find
      .descendant(
        of: of ?? find.byType(Bone),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_BoneShape',
        ),
      )
      .first,
);

/// Whether a bone paints with the sweeping gradient.
PaintPattern _shaded(bool shaded) => paints
  ..something((method, args) {
    if (method != #drawRRect) return false;
    final paint = args.last as Paint;
    if ((paint.shader != null) != shaded) {
      throw 'shader: ${paint.shader}';
    }
    return true;
  });

class _BuildCounter extends StatelessWidget {
  const _BuildCounter(this.builds);

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const Bone(width: 80, height: 12);
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadRealFonts();
  });

  group('Skeleton', () {
    Widget host(
      Widget child, {
      bool reduceMotion = false,
      bool tickers = true,
      Brightness brightness = Brightness.light,
      double textScale = 1,
    }) => MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: TickerMode(
            enabled: tickers,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

    testWidgets('sweeps by repainting bones only, never rebuilding them', (
      tester,
    ) async {
      final builds = <int>[];
      await tester.pumpWidget(host(Skeleton(child: _BuildCounter(builds))));
      expect(_ticking, greaterThan(0));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(builds, hasLength(1));
      // The highlight is a gradient over the bones.
      expect(_bone(tester), _shaded(true));
    });

    testWidgets('is still under reduced motion', (tester) async {
      await tester.pumpWidget(
        host(
          const Skeleton(child: Bone(width: 80, height: 12)),
          reduceMotion: true,
        ),
      );
      expect(_ticking, 0);
      expect(_bone(tester), paints..rrect(color: SkeletonColors.light.base));
      expect(_bone(tester), _shaded(false));
    });

    testWidgets('pauses while hidden, resumes when shown, stops when gone', (
      tester,
    ) async {
      const skeleton = Skeleton(child: Bone(width: 80, height: 12));
      await tester.pumpWidget(host(skeleton, tickers: false));
      expect(_ticking, 0);
      await tester.pumpWidget(host(skeleton));
      expect(_ticking, greaterThan(0));
      await tester.pumpWidget(host(const SizedBox()));
      expect(_ticking, 0);
    });

    testWidgets('uses dark tones in a dark theme', (tester) async {
      await tester.pumpWidget(
        host(
          const Skeleton(child: Bone(width: 80, height: 12)),
          reduceMotion: true,
          brightness: Brightness.dark,
        ),
      );
      expect(_bone(tester), paints..rrect(color: SkeletonColors.dark.base));
      expect(
        SkeletonColors.dark.base.computeLuminance(),
        lessThan(SkeletonColors.light.base.computeLuminance()),
      );
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('a text bone is as tall as its text at ${scale}x', (
        tester,
      ) async {
        for (final style in [
          AppTextStyles.titleLg,
          AppTextStyles.bodySm,
          AppTextStyles.labelSm,
        ]) {
          await tester.pumpWidget(
            host(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ag', style: style),
                  Bone.text(style, width: 40),
                ],
              ),
              textScale: scale,
            ),
          );
          expect(
            tester.getSize(find.byType(Bone)).height,
            moreOrLessEquals(
              tester.getSize(find.text('Ag')).height,
              epsilon: 1,
            ),
            reason: '${style.fontSize}',
          );
        }
      });
    }

    testWidgets('screen readers hear one label, not the shapes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const Skeleton(
            label: 'Loading medicines',
            child: Column(
              children: [Bone(width: 80, height: 12), Text('hidden')],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Loading medicines'), findsOneWidget);
      expect(find.bySemanticsLabel('hidden'), findsNothing);
      handle.dispose();
    });
  });

  group('screens', () {
    const uid = 'uid-1';
    late FakeCare careStore;
    late ProfileService profiles;
    late FakeProfiles store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Get.testMode = true;
      store = FakeProfiles()
        ..put(
          uid,
          const UserProfile(
            id: UserProfile.selfId,
            type: ProfileType.self,
            fullName: 'Eleanor Vance',
          ),
        )
        ..put(
          uid,
          const UserProfile(
            id: 'p1',
            type: ProfileType.parent,
            fullName: 'Ruth Vance',
            relationship: 'Mother / Senior Parent',
          ),
        )
        ..put(
          uid,
          const UserProfile(
            id: 'p2',
            type: ProfileType.other,
            fullName: 'Sam Vance',
          ),
        );
      profiles = ProfileService(store);
      await profiles.start(uid, selfName: 'Eleanor Vance');
      Get.put(AuthService(AuthRepository(NoAuth()), profiles)).user.value =
          FakeUser();
      careStore = FakeCare();
      seedCare(careStore);
    });

    tearDown(Get.reset);

    /// Starts the schedule services; with [slow], nothing has arrived yet.
    Completer<void>? startCare({bool slow = false}) {
      final gate = slow ? Completer<void>() : null;
      careStore.loadGate = gate;
      final care = putCare(profiles, careStore, now: fixedNow);
      Get.put(CalendarService(care, debounce: Duration.zero));
      Get.put(HistoryService(care, pageSize: 3));
      // Snapshots arrive with the screen's first pumps (the fake clock
      // only moves when the test pumps).
      return gate;
    }

    Future<void> open(
      WidgetTester tester,
      String route, {
      Object? arguments,
      Size size = const Size(400, 1400),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          initialRoute: AppRoutes.home,
          getPages: [
            for (final (name, tab) in [
              (AppRoutes.home, 0),
              (AppRoutes.medicines, 1),
              (AppRoutes.calendar, 2),
              (AppRoutes.history, 3),
              (AppRoutes.settings, 4),
            ])
              GetPage(
                name: name,
                page: () => const MainShellView(),
                binding: ShellBinding(initialTab: tab),
                transition: Transition.noTransition,
              ),
            GetPage(
              name: AppRoutes.family,
              page: () => const FamilyView(),
              binding: FamilyBinding(),
            ),
            GetPage(
              name: AppRoutes.notifications,
              page: () => const NotificationsView(),
              binding: NotificationsBinding(),
            ),
            GetPage(
              name: AppRoutes.medicineDetails,
              page: () => const MedicineDetailsView(),
              binding: MedicineDetailsBinding(),
            ),
          ],
        ),
      );
      await tester.pump();
      if (route != AppRoutes.home) {
        Get.toNamed(route, arguments: arguments);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    Future<void> tab(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.text(label),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Lets held snapshots through and settles.
    Future<void> arrive(WidgetTester tester, Completer<void> gate) async {
      gate.complete();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('slow first load: each screen shows its skeleton, then data', (
      tester,
    ) async {
      final gate = startCare(slow: true)!;
      await open(tester, AppRoutes.home);
      expect(find.bySemanticsLabel('Loading today’s schedule'), findsOneWidget);
      expect(_spinner, findsNothing);

      await tab(tester, 'Medicines');
      expect(find.bySemanticsLabel('Loading medicines'), findsOneWidget);
      await tab(tester, 'Calendar');
      expect(
        find.bySemanticsLabel('Loading this day’s schedule'),
        findsOneWidget,
      );
      await tab(tester, 'History');
      expect(find.bySemanticsLabel('Loading history'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading activity summary'), findsOneWidget);
      expect(_spinner, findsNothing);

      await arrive(tester, gate);
      expect(_skeleton, findsNothing); // and so nothing is still ticking
      expect(find.text('Vitamin D3'), findsWidgets);
      await tab(tester, 'Medicines');
      await tester.pumpAndSettle();
      expect(_skeleton, findsNothing);
      expect(find.text('Amoxicillin'), findsOneWidget);
    });

    testWidgets('slow load: Notifications and Medication Details', (
      tester,
    ) async {
      final gate = startCare(slow: true)!;
      await open(tester, AppRoutes.notifications);
      expect(find.bySemanticsLabel('Loading notifications'), findsOneWidget);
      // Never "all caught up" before anything has loaded.
      expect(find.textContaining('caught up'), findsNothing);
      Get.back();
      await tester.pump(const Duration(milliseconds: 500));

      Get.toNamed(
        AppRoutes.medicineDetails,
        arguments: const MedicineDetailsArgs(
          medicineId: 'amox',
          profileId: UserProfile.selfId,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.bySemanticsLabel('Loading medicine'), findsOneWidget);
      expect(_spinner, findsNothing);
      await arrive(tester, gate);
      expect(_skeleton, findsNothing);
      expect(find.byType(MedicineDetailsView), findsOneWidget);
      expect(find.text('Amoxicillin'), findsWidgets);
    });

    testWidgets('cached data shows without a skeleton once open', (
      tester,
    ) async {
      startCare();
      await open(tester, AppRoutes.home);
      expect(_skeleton, findsNothing);
      await tab(tester, 'Medicines');
      expect(_skeleton, findsNothing);
      expect(find.text('Amoxicillin'), findsOneWidget);
    });

    testWidgets('background updates keep the content in place', (tester) async {
      startCare();
      await open(tester, AppRoutes.medicines);
      await tab(tester, 'Medicines');
      careStore.medicinesOf(uid, 'self')['zinc'] = Medicine(
        id: 'zinc',
        name: 'Zinc',
        frequency: Frequency.onceDaily,
        doseMinutes: const [8 * 60],
        startDate: DateTime(2026, 10, 24),
        courseDays: 30,
        quantity: 30,
      );
      careStore.emit();
      await tester.pump();
      expect(_skeleton, findsNothing);
      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('Zinc'), findsOneWidget);
    });

    testWidgets('a failed load shows an error with Retry, never shimmer', (
      tester,
    ) async {
      careStore.loadFailure = const CareFailure('You’re offline.');
      startCare();
      await open(tester, AppRoutes.home);
      await tester.pumpAndSettle(); // nothing left animating
      expect(_skeleton, findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Today’s doses aren’t available'), findsOneWidget);

      await tab(tester, 'History');
      await tester.pumpAndSettle();
      expect(_skeleton, findsNothing);
      expect(find.text('Couldn’t load your history'), findsOneWidget);

      Get.toNamed(AppRoutes.notifications);
      await tester.pumpAndSettle();
      expect(_skeleton, findsNothing);
      expect(find.text('Couldn’t load your alerts'), findsOneWidget);
      expect(find.textContaining('caught up'), findsNothing);

      careStore.loadFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t load your alerts'), findsNothing);
      expect(find.text('Amoxicillin supply low'), findsOneWidget);
    });

    testWidgets('an empty profile shows its empty state', (tester) async {
      await profiles.switchTo('p2');
      startCare();
      await open(tester, AppRoutes.medicines);
      await tab(tester, 'Medicines');
      expect(_skeleton, findsNothing);
      expect(find.text('No active medicines yet'), findsOneWidget);
    });

    testWidgets('switching profile clears the old one and shows the skeleton', (
      tester,
    ) async {
      startCare();
      await open(tester, AppRoutes.medicines);
      await tab(tester, 'Medicines');
      expect(find.text('Amoxicillin'), findsOneWidget);

      final gate = Completer<void>();
      careStore.loadGate = gate;
      await profiles.switchTo('p1');
      await tester.pump();
      expect(find.text('Amoxicillin'), findsNothing);
      expect(find.bySemanticsLabel('Loading medicines'), findsOneWidget);
      await arrive(tester, gate);
      expect(_skeleton, findsNothing);
      expect(find.text('Lisinopril'), findsOneWidget);
    });

    testWidgets('older pages load as skeleton rows below the shown records', (
      tester,
    ) async {
      // Within History's default period (the week to Oct 24).
      for (var d = 18; d <= 23; d++) {
        final log = DoseLog(
          medicineId: 'vitd',
          day: DateTime(2026, 10, d),
          minutes: 9 * 60,
          status: DoseStatus.taken,
          loggedAt: DateTime(2026, 10, d, 9, 5),
          medicineName: 'Vitamin D3',
        );
        careStore.logsOf(uid, 'self')[log.id] = log;
      }
      startCare();
      await open(tester, AppRoutes.history);
      await tab(tester, 'History');
      await tester.pumpAndSettle();
      final history = Get.find<HistoryService>();
      expect(history.entries, hasLength(3));

      careStore.pageGate = Completer<void>();
      unawaited(history.loadMore());
      await tester.pump();
      // The loaded records stay; placeholders sit below them.
      expect(find.bySemanticsLabel('Loading history'), findsNothing);
      final more = find.bySemanticsLabel('Loading older records');
      await tester.scrollUntilVisible(
        more,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final lastCard = find.text('Vitamin D3').last;
      expect(
        tester.getTopLeft(more).dy,
        greaterThan(tester.getTopLeft(lastCard).dy),
      );

      careStore.pageGate!.complete();
      await tester.pumpAndSettle();
      expect(more, findsNothing);
      expect(history.entries, hasLength(6));
    });

    testWidgets('a hidden tab’s skeleton stops ticking', (tester) async {
      final gate = startCare(slow: true)!;
      await open(tester, AppRoutes.home);
      expect(_ticking, greaterThan(0));
      await tab(tester, 'Settings');
      // Home's skeleton is still there, but paused: everything settles.
      await tester.pumpAndSettle();
      expect(_ticking, 0);
      await arrive(tester, gate);
    });

    testWidgets('Family & Profiles and Settings while profiles load', (
      tester,
    ) async {
      startCare();
      profiles.status.value = ProfilesStatus.loading;
      profiles.profiles.clear();
      await open(tester, AppRoutes.settings);
      await tab(tester, 'Settings');
      expect(find.bySemanticsLabel('Loading your account'), findsOneWidget);
      Get.toNamed(AppRoutes.family);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.bySemanticsLabel('Loading profiles'), findsOneWidget);
      expect(_spinner, findsNothing);
      // Hand back a settled state so the test can end.
      await profiles.start(uid, selfName: 'Eleanor Vance', force: true);
      await tester.pumpAndSettle();
      expect(_skeleton, findsNothing);
      expect(find.text('Your Profiles'), findsOneWidget);
    });
  });
}
