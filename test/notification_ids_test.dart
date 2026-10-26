import 'package:dosemate/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification ids are stable, positive 31-bit and key-specific', () {
    const key = 'dose:self:m1_2026-10-25_480';
    final id = NotificationService.idFor(key);
    expect(NotificationService.idFor(key), id);
    expect(id, inInclusiveRange(0, 0x7fffffff));
    expect(NotificationService.idFor('supply:self:m1'), isNot(id));
  });
}
