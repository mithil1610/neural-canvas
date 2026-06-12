import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AssetAnalyzerService {
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static Future<void> analyzeIngestedAsset(String docId, String fileUrl, String fileType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("AssetAnalyzer: No user logged in.");
      return;
    }
    
    if (_geminiApiKey.isEmpty) {
      debugPrint("AssetAnalyzer: GEMINI_API_KEY is missing. Cannot perform AI analysis.");
      await _updateSummary(docId, "AI Analysis unavailable (Missing API Key)");
      return;
    }

    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _geminiApiKey,
    );

    try {
      String aiSummary = "Processing semantic data...";
      
      if (fileType == 'png' || fileType == 'jpeg' || fileType == 'jpg') {
        // Multi-modal Vision Request
        final response = await http.get(Uri.parse(fileUrl));
        final bytes = response.bodyBytes;
        
        final content = [
          Content.multi([
            DataPart('image/jpeg', bytes),
            TextPart("Analyze this image. Provide a clean summary paragraph listing objects, text, and context."),
          ])
        ];
        
        final responseGemini = await model.generateContent(content);
        
        aiSummary = responseGemini.text ?? "Could not extract meaning from image.";
      } else {
         // Text/PDF metadata-based generic reading for now
         final prompt = TextPart("You are a semantic indexer for a knowledge base. The user just uploaded a file of type: $fileType. Generate a short, highly structured 2-sentence summary acknowledging this document type and suggesting it might contain structured formatting, text, or tabular data. Do not invent details you cannot see, just provide a metadata-based structural acknowledgment.");
         
         final responseGemini = await model.generateContent([
           Content.text(prompt.text)
         ]);
         
         aiSummary = responseGemini.text ?? "Document successfully indexed.";
      }
      
      await _updateSummary(docId, aiSummary.trim());
      debugPrint("AssetAnalyzer: Successfully generated summary for $docId");
        
    } catch (e) {
      debugPrint("AssetAnalyzer failed: $e");
      await _updateSummary(docId, "Analysis encountered an error.");
    }
  }

  static Future<void> _updateSummary(String docId, String summary) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('knowledge_base')
        .doc(docId)
        .update({'aiSummary': summary});
  }
}
