import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neural_canvas/models/chat_message.dart';

class AiService {
  // Singleton pattern
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;

  // Global Chat History
  final ValueNotifier<List<ChatMessage>> chatHistory = ValueNotifier([
    const ChatMessage(
      text: 'Hello! I am your Digital Memory Assistant. How can I help you explore your canvas today?',
      isAssistant: true,
    )
  ]);

  String? currentSessionId;

  AiService._internal();

  /// Called from the UI when a user types a message.
  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _addMessage(ChatMessage(text: trimmed, isAssistant: false));
    await _callBackendFunction(trimmed);
  }

  /// Called from background services when a file is shared or processed.
  Future<String> sendSystemContext(String contextText, {String? mediaPath, String? mediaType}) async {
    _addMessage(const ChatMessage(
      text: "Analyzing shared asset...",
      isAssistant: false,
      isSystem: true,
    ));

    final result = await _callBackendFunction(contextText, mediaPath: mediaPath, mediaType: mediaType);
    return result;
  }

  /// Internal helper to call the secure Firebase Callable Function
  Future<String> _callBackendFunction(String prompt, {String? mediaPath, String? mediaType}) async {
    // Add empty assistant message that is streaming
    _addMessage(const ChatMessage(text: '', isAssistant: true, isStreaming: true));

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('analyzeMedia');
      
      final Map<String, dynamic> payload = {
        'prompt': prompt,
      };

      if (mediaPath != null && mediaType != null) {
        payload['mediaPath'] = mediaPath;
        payload['mediaType'] = mediaType;
      }

      final results = await callable.call(payload);
      
      final String aiResponse = results.data['response'] as String;

      // Update the streaming message with the final result
      final messages = List<ChatMessage>.from(chatHistory.value);
      final lastIndex = messages.length - 1;
      
      messages[lastIndex] = messages[lastIndex].copyWith(
        text: aiResponse,
        isStreaming: false,
      );
      
      chatHistory.value = messages;
      return aiResponse;

    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint("Firebase Functions Error [${e.code}]: ${e.message}");
      
      String errorMsg = "Error connecting to Neural Core.";
      if (e.code == 'resource-exhausted') {
        errorMsg = "You've reached your daily limit for AI requests.";
      } else if (e.code == 'unauthenticated') {
        errorMsg = "You must be securely logged in to access the AI.";
      }
      
      final messages = List<ChatMessage>.from(chatHistory.value);
      final lastIndex = messages.length - 1;
      messages[lastIndex] = messages[lastIndex].copyWith(
        text: "\n\n**Error:** $errorMsg",
        isStreaming: false,
      );
      chatHistory.value = messages;
      return errorMsg;
    } catch (e) {
      final messages = List<ChatMessage>.from(chatHistory.value);
      final lastIndex = messages.length - 1;
      messages[lastIndex] = messages[lastIndex].copyWith(
        text: "\n\n**Error:** An unexpected network error occurred.",
        isStreaming: false,
      );
      chatHistory.value = messages;
      return "Error";
    }
  }

  void _addMessage(ChatMessage message) {
    chatHistory.value = [...chatHistory.value, message];
  }

  void clearHistory() {
    currentSessionId = null;
    chatHistory.value = [
      const ChatMessage(
        text: 'Hello! I am your Digital Memory Assistant. How can I help you explore your canvas today?',
        isAssistant: true,
      )
    ];
  }

  Future<void> loadSession(String sessionId) async {
    currentSessionId = sessionId;
    chatHistory.value = [];
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chats')
          .doc(sessionId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .get();

      if (snapshot.docs.isEmpty) {
        clearHistory();
        return;
      }

      chatHistory.value = snapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          text: data['text'] ?? '',
          isAssistant: data['isAssistant'] ?? false,
          isSystem: data['isSystem'] ?? false,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint("Error loading session: $e");
      clearHistory();
    }
  }
}
