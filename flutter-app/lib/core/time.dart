/// Fixed Iraq timezone (Asia/Baghdad, UTC+3, no DST).
/// DB/API keep UTC; UI formats through [toIraq].
library;

const iraqOffset = Duration(hours: 3);

/// Normalize any timestamp to a UTC instant.
DateTime asUtc(DateTime d) {
  if (d.isUtc) return d;
  // Device-local → real UTC.
  if (d.timeZoneOffset != Duration.zero) return d.toUtc();
  // Unspecified with zero offset: treat as UTC wall (API bare datetime).
  return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}

/// Wall-clock in Iraq for DateFormat (Unspecified).
DateTime toIraq(DateTime d) => asUtc(d).add(iraqOffset);

DateTime iraqNow() => DateTime.now().toUtc().add(iraqOffset);

/// Parse API date strings as UTC instants.
DateTime? parseApiDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return asUtc(raw);
  final x = '$raw';
  final d = DateTime.tryParse(x);
  if (d == null) return null;
  if (d.isUtc || x.endsWith('Z') || x.contains('+') || RegExp(r'-\d{2}:\d{2}$').hasMatch(x)) {
    return d.toUtc();
  }
  return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond, d.microsecond);
}
