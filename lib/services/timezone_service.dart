import 'package:flutter_timezone/flutter_timezone.dart';

class TimezoneService {
  /// Returns the device's IANA timezone identifier (e.g. "America/Chicago", "Europe/London").
  static Future<String> getDeviceTimezone() async {
    try {
      final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone();
      return tzInfo.identifier;
    } catch (e) {
      // Fallback to UTC if timezone lookup fails
      return 'UTC';
    }
  }

  /// Returns the current local date in YYYY-MM-DD format.
  static String getCurrentLocalDate() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
