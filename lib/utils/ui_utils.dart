import 'package:flutter/material.dart';

class UIUtils {
  static void showFloatingSnackBar(BuildContext context, String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 24, right: 24),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dismissDirection: DismissDirection.down,
        action: action,
      ),
    );
  }
}
