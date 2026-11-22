import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static const String _keyAutoFiledCount = 'review_auto_filed_count';
  static const String _keyEventReminderCreated = 'review_event_reminder_created';
  static const String _keyLastReviewTimestamp = 'review_last_request_timestamp';
  static const String _keyHasLaunchedBefore = 'review_has_launched_before';

  static final InAppReview _inAppReview = InAppReview.instance;

  /// Call once upon app startup to establish first-launch tracking.
  static Future<void> markAppLaunched() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyHasLaunchedBefore)) {
      // First time app has ever launched. Set to false so we do not prompt on launch 1.
      await prefs.setBool(_keyHasLaunchedBefore, false);
    } else {
      // Subsequent launches. Mark as launched before.
      await prefs.setBool(_keyHasLaunchedBefore, true);
    }
  }

  /// Triggered after an item is successfully auto-filed in the vault.
  static Future<void> checkAutoFiledMilestone() async {
    final prefs = await SharedPreferences.getInstance();
    int count = prefs.getInt(_keyAutoFiledCount) ?? 0;
    count += 1;
    await prefs.setInt(_keyAutoFiledCount, count);

    if (count == 3) {
      await _maybeRequestReview(prefs, reason: '3rd auto-filed item');
    }
  }

  /// Triggered when an event reminder notification is first scheduled.
  static Future<void> checkEventReminderMilestone() async {
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyTriggered = prefs.getBool(_keyEventReminderCreated) ?? false;
    if (alreadyTriggered) return;

    await prefs.setBool(_keyEventReminderCreated, true);
    await _maybeRequestReview(prefs, reason: 'First event reminder created');
  }

  static Future<void> _maybeRequestReview(SharedPreferences prefs, {required String reason}) async {
    // 1. Never on first launch
    final bool hasLaunchedBefore = prefs.getBool(_keyHasLaunchedBefore) ?? false;
    if (!hasLaunchedBefore) {
      if (kDebugMode) {
        debugPrint("Review prompt skipped: First launch period active.");
      }
      return;
    }

    // 2. Never more than once per 90 days
    final int lastTimestamp = prefs.getInt(_keyLastReviewTimestamp) ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    const int ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;

    if (now - lastTimestamp < ninetyDaysMs) {
      if (kDebugMode) {
        debugPrint("Review prompt skipped: 90-day cooldown active.");
      }
      return;
    }

    // 3. Request in-app review
    try {
      if (await _inAppReview.isAvailable()) {
        if (kDebugMode) {
          debugPrint("Requesting In-App Review (Trigger: $reason)...");
        }
        await _inAppReview.requestReview();
        await prefs.setInt(_keyLastReviewTimestamp, now);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("In-app review request failed: $e");
      }
    }
  }
}
