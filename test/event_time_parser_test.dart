import 'package:flutter_test/flutter_test.dart';
import 'package:neural_canvas/utils/event_time_parser.dart';

void main() {
  group('EventTimeParser Tests', () {
    test('parses ISO8601 with explicit timezone offset', () {
      const dateStr = '2026-10-12T14:30:00-05:00';
      final parsed = EventTimeParser.parseEventDateTime(dateStr);
      expect(parsed, isNotNull);
      // Ensure it parsed to a valid DateTime instance
      expect(parsed!.year, 2026);
      expect(parsed.month, 10);
    });

    test('parses local wall time with no offset as device-local time', () {
      // The server returns local wall-clock time, so a 2:30 PM appointment stays
      // 2:30 PM on the device, including after a daylight-saving change.
      const dateStr = '2027-03-20T14:30:00';
      final parsed = EventTimeParser.parseEventDateTime(dateStr);
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
      expect(parsed.year, 2027);
      expect(parsed.month, 3);
      expect(parsed.day, 20);
      expect(parsed.hour, 14);
      expect(parsed.minute, 30);
    });

    test('reminder for a post-DST event is 30 minutes before local time', () {
      final parsed = EventTimeParser.parseEventDateTime('2027-03-20T14:30:00')!;
      final reminder = EventTimeParser.calculateReminderTime(parsed);
      expect(reminder.hour, 14);
      expect(reminder.minute, 0);
      expect(reminder.day, 20);
    });

    test('parses date-only string and defaults to 09:00:00 local time', () {
      const dateStr = '2026-12-25';
      final parsed = EventTimeParser.parseEventDateTime(dateStr);
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 12);
      expect(parsed.day, 25);
      expect(parsed.hour, 9);
      expect(parsed.minute, 0);
    });

    test('returns null for TBD, empty, or invalid strings', () {
      expect(EventTimeParser.parseEventDateTime(null), isNull);
      expect(EventTimeParser.parseEventDateTime(''), isNull);
      expect(EventTimeParser.parseEventDateTime('TBD'), isNull);
      expect(EventTimeParser.parseEventDateTime('not-a-date'), isNull);
    });

    test('calculates reminder 30 minutes before timed event', () {
      final eventTime = DateTime(2026, 11, 25, 15, 0); // 3:00 PM
      final reminder = EventTimeParser.calculateReminderTime(eventTime);
      expect(reminder, DateTime(2026, 11, 25, 14, 30)); // 2:30 PM
    });

    test('calculates reminder at 09:00 for date-only event', () {
      final eventTime = DateTime(2026, 11, 25, 9, 0);
      final reminder = EventTimeParser.calculateReminderTime(eventTime, isDateOnly: true);
      expect(reminder, DateTime(2026, 11, 25, 9, 0));
    });

    test('shouldSchedule returns true for future events and false for past events', () {
      final now = DateTime(2026, 11, 22, 12, 0);
      final futureReminder = DateTime(2026, 11, 22, 12, 30);
      final pastReminder = DateTime(2026, 11, 22, 11, 30);

      expect(EventTimeParser.shouldSchedule(futureReminder, now), isTrue);
      expect(EventTimeParser.shouldSchedule(pastReminder, now), isFalse);
    });
  });
}
