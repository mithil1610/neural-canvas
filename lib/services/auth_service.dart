import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import '../ui/modals/paywall_sheet.dart';

class AuthService {
  // 📈 TRACKS TOTAL MONTHLY COMPUTE STORAGE
  static Future<bool> checkAndIncrementUsage(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final uid = user.uid;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? {};
      final String accountTier = data['accountTier'] ?? 'Free';
      final int aiUsageCount = data['aiUsageCount'] ?? 0;

      int limit = (accountTier == 'Free')
          ? 200
          : (accountTier == 'Creation Engine' ? 750 : 3000);

      if (aiUsageCount >= limit) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AlertDialog(
                  backgroundColor: Theme.of(
                    ctx,
                  ).colorScheme.surface.withValues(alpha: 0.8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  title: const Text(
                    'Bandwidth Reached',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: const Text(
                    "You've reached your monthly capacity allocation threshold. Your Second Brain values will refresh next month!",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Understood',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }
        return false;
      }

      // Usage counters are incremented on the server inside transaction
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint(
          "⚠️ Security breach or ghost account detected. Forcing local sign-out.",
        );
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

      final String todayDate = DateTime.now().toIso8601String().split('T')[0];

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
