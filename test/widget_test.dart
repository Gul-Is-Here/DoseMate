import 'package:flutter_test/flutter_test.dart';

import 'package:dosemate/main.dart';

void main() {
  testWidgets('Onboarding shows first page', (tester) async {
    await tester.pumpWidget(const DoseMateApp());
    await tester.pumpAndSettle();

    expect(find.text('Never Miss a Scheduled Dose'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
  });
}
