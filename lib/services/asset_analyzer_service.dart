import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:neural_canvas/services/notification_service.dart';
import 'package:neural_canvas/services/timezone_service.dart';
import 'package:neural_canvas/services/review_service.dart';
import 'package:neural_canvas/utils/event_time_parser.dart';
import 'package:neural_canvas/main.dart';
import 'package:neural_canvas/utils/ui_utils.dart';

class AssetAnalyzerService {
  static Future<void> analyzeIngestedAsset(
    String docId,
    String fileUrl,
    String fileType,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (kDebugMode) debugPrint("AssetAnalyzer: No user logged in.");
      return;
    }

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'analyzeAsset',
      );

      final result = await callable.call({
        'docId': docId,
        'fileUrl': fileUrl,
        'fileType': fileType,
      });

      final data = result.data as Map<dynamic, dynamic>? ?? {};
      final summaryToSave = data['summary']?.toString() ?? '';

      if (kDebugMode) {
        debugPrint("AssetAnalyzer: Server analysis complete for $docId");
      }

      // Growth check: Positive moment milestone (3rd auto-filed item)
      await ReviewService.checkAutoFiledMilestone();

      if (summaryToSave.isNotEmpty) {
        await extractEvents(docId, summaryToSave);
      }
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint("AssetAnalyzer functions error [${e.code}]: ${e.message}");
      }
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        if (e.code == 'resource-exhausted') {
          UIUtils.showFloatingSnackBar(
            context,
            e.message ?? "Daily upload limit reached.",
          );
        } else {
          UIUtils.showFloatingSnackBar(
            context,
            "Analysis encountered an issue: ${e.message}",
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("AssetAnalyzer failed: $e");
    }
  }

  static Future<void> extractEvents(String docId, String summaryText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || summaryText.trim().isEmpty) return;

    try {
      final String userTimezone = await TimezoneService.getDeviceTimezone();
      final String currentDate = TimezoneService.getCurrentLocalDate();

      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
        'extractEvents',
      );

      final result = await callable.call({
        'docId': docId,
        'summaryText': summaryText,
        'timezone': userTimezone,
        'currentDate': currentDate,
      });

      final data = result.data as Map<dynamic, dynamic>? ?? {};
      final List<dynamic> events = data['events'] as List<dynamic>? ?? [];

      if (events.isNotEmpty) {
        for (var event in events) {
          final title = event['eventTitle']?.toString() ?? 'Upcoming Event';
          final dateTimeStr = event['eventDateTime']?.toString() ?? 'TBD';
          final location = event['eventLocation']?.toString() ?? 'TBD';

          final DateTime? eventDt = EventTimeParser.parseEventDateTime(dateTimeStr);
          if (eventDt != null) {
            final bool isDateOnly = dateTimeStr.length == 10;
            final DateTime triggerTime = EventTimeParser.calculateReminderTime(
              eventDt,
              isDateOnly: isDateOnly,
            );

            if (EventTimeParser.shouldSchedule(triggerTime)) {
              await NotificationService.scheduleEventNotification(
                title: "Upcoming Event • $title",
                body: "$location - Tap to view your Chronos Matrix.",
                scheduledDate: triggerTime,
              );

              // Growth check: Positive moment milestone (First event reminder created)
              await ReviewService.checkEventReminderMilestone();
            }
          }
        }

        if (kDebugMode) {
          debugPrint("AssetAnalyzer: Successfully extracted ${events.length} events for $docId");
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("AssetAnalyzer event extraction failed: $e");
    }
  }
}
