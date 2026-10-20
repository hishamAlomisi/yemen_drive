import 'dart:math' as math;

/// A display projection of a server-approved waiting session, never a charge.
class RideWaitingSnapshot {
  RideWaitingSnapshot(this.data) {
    if (date(data['serverNowUtc']) == null) {
      throw const FormatException('تعذرت قراءة حالة الانتظار من الخادم.');
    }
  }

  final Map<String, Object?> data;
  Map<String, Object?> get session => data['session'] is Map
      ? Map<String, Object?>.from(data['session'] as Map)
      : const {};
  bool get isOpen => session['isOpen'] == true;
  bool get isActive => isOpen && date(session['startedAtUtc']) != null;

  static double number(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value : 0;
  }

  static DateTime? date(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString();
    return DateTime.tryParse(
      text.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(text)
          ? text
          : '${text}Z',
    )?.toUtc();
  }

  DateTime projectedNow(Duration elapsed) {
    var now = date(data['serverNowUtc'])!
        .add(Duration(milliseconds: elapsed.inMilliseconds.clamp(0, 15000)));
    final deadline = date(data['connectionDeadlineUtc']);
    if (deadline != null && now.isAfter(deadline)) now = deadline;
    return now;
  }

  int elapsedSeconds(Duration elapsed) => isActive
      ? math.max(
          0,
          projectedNow(elapsed)
              .difference(date(session['startedAtUtc'])!)
              .inSeconds,
        )
      : 0;

  double waitingFee(Duration elapsed) {
    if (!isActive) return number(data['waitingFee']);
    // Preserve fractional seconds until rounding, matching the server's
    // midpoint-away-from-zero rounding for nonnegative monetary values.
    final seconds = math.max(
      0,
      projectedNow(elapsed)
                  .difference(date(session['startedAtUtc'])!)
                  .inMicroseconds /
              Duration.microsecondsPerSecond -
          number(session['freeMinutes']) * 60,
    );
    final fee = math.min(
      number(session['maxFee']),
      (seconds * number(session['pricePerMinute']) / 60).roundToDouble(),
    );
    return number(data['settledWaitingFee']) + fee;
  }

  double totalAmount(Duration elapsed) =>
      number(data['totalAmount']) +
      waitingFee(elapsed) -
      number(data['waitingFee']);
}
