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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = userDoc.data() ?? {};
      final String accountTier = data['accountTier'] ?? 'free';
      final int aiUsageCount = data['aiUsageCount'] ?? 0;

      int limit = 15;
      if (accountTier == 'premium' || accountTier == 'pro') {
        limit = 750;
      } else if (accountTier == 'infinite') {
        limit = 3000;
      }

      if (aiUsageCount >= limit) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AlertDialog(
                  backgroundColor: Theme.of(ctx).colorScheme.surface.withValues(alpha: 0.8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                  ),
                  title: const Text('Neural Bandwidth Maximized', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: const Text(
                    "Your monthly AI processing frames reset next month. Upgrade now to expand your brain's capacity instantly.",
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Dismiss', style: TextStyle(color: Colors.white60)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Upgrade', style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold)),
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
        'aiUsageCount': FieldValue.increment(1)
      });
      return true;

    } catch (e) {
      if (kDebugMode) debugPrint("Error checking usage: $e");
      return false; 
    }
  }
}
