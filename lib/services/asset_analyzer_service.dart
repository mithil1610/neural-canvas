import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';

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
      await _updateSummaryAndTitle(docId, "AI Analysis unavailable (Missing API Key)", _fallbackTitle());
      return;
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _geminiApiKey,
    );

    try {
      String mimeType = 'image/jpeg';
      String systemPrompt = 'Analyze this asset comprehensively.';

      if (fileType == 'pdf') {
        mimeType = 'application/pdf';
        systemPrompt = 'Extract all textual data via deep OCR. Identify core concepts, critical names, data points, entities, and provide an exhaustive analytical summary.';
      } else if (['mp3', 'm4a', 'wav'].contains(fileType)) {
        mimeType = 'audio/mp3';
        systemPrompt = 'Listen to this audio track carefully. Transcribe the spoken text entirely, analyze the conversational tone, summarize the core topics discussed, and output key takeaways.';
      } else if (['mp4', 'mov'].contains(fileType)) {
        mimeType = 'video/mp4';
        systemPrompt = 'Watch this video clip sequentially. Detect key scenes, summarize visual actions, transcribe background audio tracks, and create a timeline summary of what occurs.';
      } else {
        mimeType = 'image/jpeg';
        systemPrompt = 'Perform an image analysis. Read any overlay text via OCR, detect visible objects, actions, human expressions, emotional mood, and summarize the overall context.';
      }

      systemPrompt += ' Additionally, generate a highly contextual, punchy title (maximum 5 words) that perfectly describes this asset. Format your response strictly as JSON: { "title": "...", "summary": "..." }';

      final response = await http.get(Uri.parse(fileUrl));
      final bytes = response.bodyBytes;
      
      final content = [
        Content.multi([
          DataPart(mimeType, bytes),
          TextPart(systemPrompt),
        ])
      ];
      
      final responseGemini = await model.generateContent(content);
      final rawText = responseGemini.text ?? "{}";
      
      String titleToSave;
      String summaryToSave = "Could not extract meaning from asset.";

      try {
        String jsonText = rawText;
        if (jsonText.contains('```json')) {
            jsonText = jsonText.split('```json')[1].split('```')[0].trim();
        } else if (jsonText.contains('{')) {
            jsonText = jsonText.substring(jsonText.indexOf('{'), jsonText.lastIndexOf('}') + 1);
        }
        final Map<String, dynamic> parsed = jsonDecode(jsonText);
        titleToSave = parsed['title']?.toString() ?? _fallbackTitle();
        if (parsed['summary'] != null) {
          summaryToSave = parsed['summary'].toString();
        } else {
          summaryToSave = rawText.trim();
        }
      } catch (e) {
         titleToSave = _fallbackTitle();
         summaryToSave = rawText.trim();
      }

      await _updateSummaryAndTitle(docId, summaryToSave, titleToSave);
      debugPrint("AssetAnalyzer: Successfully generated summary and title for $docId");
      
      // Secondary pass for Chronos Lens Event Extractor
      await extractEvents(docId, summaryToSave);
        
    } catch (e) {
      debugPrint("AssetAnalyzer failed: $e");
      await _updateSummaryAndTitle(docId, "Analysis encountered an error.", _fallbackTitle());
    }
  }

  static String _fallbackTitle() {
    final now = DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    int hr = now.hour % 12;
    if (hr == 0) hr = 12;
    final min = now.minute.toString().padLeft(2, '0');
    return "Note • ${months[now.month - 1]} ${now.day}, $hr:$min $amPm";
  }

  static Future<void> _updateSummaryAndTitle(String docId, String summary, String title) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('knowledge_base')
        .doc(docId)
        .update({
          'aiSummary': summary,
          'smartTitle': title,
        });
  }

  static Future<void> extractEvents(String docId, String summaryText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _geminiApiKey.isEmpty) return;

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );

    try {
      final prompt = """
Analyze the following text for any identifiable timeline variables or scheduled events (e.g., meeting dates, locations, calendar slots, appointment confirmations).
If events are found, return a JSON array of objects, where each object has these strictly named string keys: "eventTitle", "eventDateTime", "eventLocation".
If no events are found, return an empty JSON array [].

Text: $summaryText
""";
      final response = await model.generateContent([Content.text(prompt)]);
      if (response.text != null) {
        final List<dynamic> events = jsonDecode(response.text!);
        if (events.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          final eventsRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('upcoming_events');
          
          for (var event in events) {
            final newDoc = eventsRef.doc();
            batch.set(newDoc, {
              'sourceDocId': docId,
              'eventTitle': event['eventTitle']?.toString() ?? 'Unknown Event',
              'eventDateTime': event['eventDateTime']?.toString() ?? 'TBD',
              'eventLocation': event['eventLocation']?.toString() ?? 'TBD',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          debugPrint("AssetAnalyzer: Successfully extracted \${events.length} events for $docId");
        }
      }
    } catch (e) {
      debugPrint("AssetAnalyzer event extraction failed: $e");
    }
  }
}
