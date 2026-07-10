import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyHelper {
  static Future<bool> ensureAIConsent(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    bool hasConsented = prefs.getBool('has_consented_to_gemini_ai') ?? false;

    if (hasConsented) {
      return true;
    }

    // Since this can be called from asynchronous gaps, ensure context is mounted.
    if (!context.mounted) return false;

    bool? dialogResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "AI Integration Consent",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(
                      "To summarize and map your notes, Axiom securely processes your documents and text via Google Gemini AI. Data is encrypted in transit and handled strictly in accordance with our Privacy Policy. Do you agree to this processing?",
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                await prefs.setBool('has_consented_to_gemini_ai', true);
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text("I Agree & Continue"),
            ),
          ],
        );
      },
    );

    return dialogResult ?? false;
  }
}
