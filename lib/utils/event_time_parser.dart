class EventTimeParser {
  /// Parses an event time returned by the server.
  ///
  /// Since 1.3.0 the server returns LOCAL wall-clock time with no offset
  /// ("2026-12-15T10:30:00") or a date only ("2026-12-15"). Dart parses a string
  /// without an offset as local time, so the reminder lands at the right local
  /// hour even across daylight-saving changes. Strings with an offset or "Z"
  /// (older data) are still accepted and converted to local time.
  /// If the event has only a date (e.g., "2026-10-12"), it defaults to 09:00:00 local time.
  /// Returns null if the string cannot be parsed or is 'TBD'.
  static DateTime? parseEventDateTime(String? rawStr) {
    if (rawStr == null) return null;
    final trimmed = rawStr.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == 'TBD') return null;

    // Check for date-only pattern: YYYY-MM-DD
    final dateOnlyRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateOnlyRegex.hasMatch(trimmed)) {
      final parts = trimmed.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      return DateTime(year, month, day, 9, 0);
    }

    try {
      final parsed = DateTime.parse(trimmed);
      // Convert to local time to ensure device timezone alignment
      return parsed.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Calculates the notification trigger time.
  /// If the event had date only (defaults to 09:00:00), the reminder is at 09:00:00 that morning.
  /// Otherwise, reminder is 30 minutes prior to the event time.
  static DateTime calculateReminderTime(DateTime eventTime, {bool isDateOnly = false}) {
    if (isDateOnly) {
      return DateTime(
        eventTime.year,
        eventTime.month,
        eventTime.day,
        9,
        0,
      );
    }
    return eventTime.subtract(const Duration(minutes: 30));
  }

  /// Checks if the calculated reminder time is in the future.
  /// Returns true only if the event reminder is in the future.
  static bool shouldSchedule(DateTime reminderTime, [DateTime? referenceNow]) {
    final now = referenceNow ?? DateTime.now();
    return reminderTime.isAfter(now);
  }
}
