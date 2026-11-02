import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/utils/utc_timestamp.dart';

void main() {
  test('SQL timestamps without a zone retain the instant of the live GPS event', () {
    final snapshot = parseUtcTimestamp('2026-11-02T18:15:20.123456');
    final live = parseUtcTimestamp('2026-11-02T18:15:20.123456Z');
    expect(snapshot?.isUtc, true);
    expect(snapshot, live);
    expect(parseUtcTimestamp('2026-11-02T21:15:20.123456+03:00'), live);
  });
}
