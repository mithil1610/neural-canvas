import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../ui/modals/paywall_sheet.dart';

class AuthService {
  /// Pre-flight check before an AI action (chat, generation).
  ///
  /// Limits are enforced on the server per UTC day (see TIER_CONFIG in
  /// functions/index.js); when one is hit, the callable returns
  /// `resource-exhausted` with a message the UI shows. The old lifetime cap of
  /// 200 AI actions was removed: nothing ever reset it, so free users were
  /// locked out permanently.
  static Future<bool> checkAndIncrementUsage(BuildContext context) async {
    return FirebaseAuth.instance.currentUser != null;
  }

  // 🛑 TRACKS STRICT DAILY UPLOAD FLIGHT CEILINGS (ISOLATED FIELD PROFILES)
  static Future<bool> checkUserUploadQuota(
    BuildContext context, [
    String? userId,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final uid = userId ?? user.uid;

    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userDoc = await userRef.get();
      final data = userDoc.data() ?? {};
      final String accountTier = data['accountTier'] ?? 'Free';
      int dailyUploadCount = data['dailyUploadCount'] ?? 0;
      final String lastUploadDate = data['lastUploadDate'] ?? '';

      final String todayDate = DateTime.now().toUtc().toIso8601String().split('T')[0];

      if (lastUploadDate != todayDate) {
        dailyUploadCount = 0;
      }

      if (accountTier == 'Free') {
        if (dailyUploadCount >= 10) {
          if (context.mounted) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const PaywallSheet(),
            );
          }
          return false;
        }
      }

      // Server enforces and increments the daily upload counter
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login_or_register', (route) => false);
        }
        return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Quota is managed and incremented on server
  static Future<void> incrementDailyUploadQuota() async {
    // Server functions handle quota incrementation inside Firestore transactions
  }
}
