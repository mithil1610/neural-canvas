import 'dart:io';
import 'package:neural_canvas/services/ai_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as p;

/// Handles decomposition of shared assets (images, videos, PDFs, text)
/// by securely uploading them to Firebase Storage and routing to Gemini.
class DecompositionService {
  // Singleton
  static final DecompositionService _instance =
      DecompositionService._internal();
  factory DecompositionService() => _instance;

  final AiService _aiService = AiService();

  DecompositionService._internal();

  /// Analyzes a shared file by uploading it and sending the path to the AI backend.
  Future<String> analyzeSharedAsset({
    required String filePath,
    required String fileType,
  }) async {
    final file = File(filePath);

    if (!await file.exists()) {
      return 'Error: The shared file could not be found at path: $filePath';
    }

    final prompt = _buildPromptForType(fileType, filePath);
    final fileName = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase();

    // Determine basic mime type
    String mimeType = 'application/octet-stream';
    if (fileType == 'image') mimeType = 'image/${ext.replaceFirst('.', '')}';
    if (fileType == 'video') mimeType = 'video/${ext.replaceFirst('.', '')}';
    if (fileType == 'pdf') mimeType = 'application/pdf';
    if (fileType == 'text') mimeType = 'text/plain';

    // Default to jpeg if parsing fails
    if (mimeType == 'image/jpg') mimeType = 'image/jpeg';

    // Upload to Firebase Storage
    String? storagePath;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        storagePath = 'users/${user.uid}/uploads/${timestamp}_$fileName';

        final ref = FirebaseStorage.instance.ref().child(storagePath);
        final metadata = SettableMetadata(contentType: mimeType);

        await ref.putFile(file, metadata);
      } else {
        return 'Error: You must be logged in to process files.';
      }
    } catch (e) {
      return 'Error: Failed to securely upload the shared file. ($e)';
    }

    // Forward the context string and the media payload to the backend
    final result = await _aiService.sendSystemContext(
      prompt,
      mediaPath: storagePath,
      mediaType: mimeType,
    );

    return result;
  }

  String _buildPromptForType(String fileType, String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;

    switch (fileType) {
      case 'image':
        return 'The user just shared an image file named "$fileName" with Axiom. '
            'Acknowledge receipt of this image. In a real scenario, you would analyze it using your vision capabilities. '
            'For now, describe what you would do: perform OCR if it contains text, identify objects and scenes, '
            'and suggest how to categorize it in their memory archive.';
      case 'video':
        return 'The user just shared a video file named "$fileName" with Axiom. '
            'Acknowledge receipt of this video. Describe how you would process it: '
            'extract key frames, identify scenes and people, transcribe any audio, '
            'and suggest creating a memory reel from its highlights.';
      case 'pdf':
        return 'The user just shared a PDF document named "$fileName" with Axiom. '
            'Acknowledge receipt. Describe how you would process it: '
            'perform full OCR and text extraction, identify if it is a lease, contract, or general document, '
            'extract key dates, parties, and obligations, and add it to their knowledge graph.';
      case 'text':
        return 'The user just shared a text note or link with Axiom. '
            'Acknowledge receipt and describe how you would process it: '
            'parse the content, identify key topics, extract any URLs, '
            'and suggest connections to existing memories.';
      default:
        return 'The user shared a file named "$fileName" of type "$fileType". '
            'Acknowledge receipt and suggest how Axiom could process it.';
    }
  }
}
