import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';

class AuthService {
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
      final String accountTier = data['accountTier'] ?? 'free';
      final int aiUsageCount = data['aiUsageCount'] ?? 0;

      int limit = (accountTier == 'free')
          ? 200
          : (accountTier == 'premium' || accountTier == 'pro' ? 750 : 3000);

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
                    'Beta Bandwidth Reached',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: Text(
                    "You've used $limit / $limit of your free monthly Beta frames. Your Second Brain capacity will reset next month!",
                    style: const TextStyle(color: Colors.white70),
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

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'aiUsageCount': FieldValue.increment(1),
      });
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint("Error checking usage: $e");
      return false;
    }
  }

  static Future<bool> checkDailyUploadQuota(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final uid = user.uid;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? {};
      final String accountTier = data['accountTier'] ?? 'free';
      int aiUsageCount = data['aiUsageCount'] ?? 0;
      final String lastUploadDate = data['lastUploadDate'] ?? '';

      final String todayDate = DateTime.now().toIso8601String().split('T')[0];

      if (lastUploadDate != todayDate) {
        aiUsageCount = 0;
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'aiUsageCount': 0,
          'lastUploadDate': todayDate,
        });
      }

      if (accountTier == 'free' && aiUsageCount >= 10) {
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
                    'Daily Upload Limit Reached',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: const Text(
                    "Please upgrade to Axiom Premium to unlock unlimited neural storage processing.",
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
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint("Error checking daily quota: $e");
      return false;
    }
  }

  static Future<void> incrementDailyUploadQuota() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'aiUsageCount': FieldValue.increment(1)},
      );
    } catch (e) {
      if (kDebugMode) debugPrint("Error incrementing daily quota: $e");
    }
  }
}
