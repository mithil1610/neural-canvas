import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  /// Simple look-up method to check if the user is a premium subscriber.
  /// Pulls from the 'accountTier' field inside the root /users/{uid} Firestore document.
  static Future<bool> isUserPremium(String uid) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null &&
            (data['accountTier'] == 'Creation Engine' ||
                data['accountTier'] == 'Infinite Brain')) {
          return true;
        }
      }
    } catch (e) {
      // On error, securely default to free account behavior
      return false;
    }
    return false;
  }
}
