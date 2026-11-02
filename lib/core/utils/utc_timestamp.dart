/// API fields named *AtUtc retain UTC meaning when SQL removes the DateTime
/// kind and JSON therefore omits the trailing Z.
DateTime? parseUtcTimestamp(Object? value) {
  final parsed = DateTime.tryParse('$value');
  if (parsed == null || parsed.isUtc) return parsed;
  return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
      parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
}
