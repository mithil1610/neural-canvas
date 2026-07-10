import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:neural_canvas/widgets/ai_processing_overlay.dart';
import 'package:neural_canvas/services/asset_analyzer_service.dart';
import 'package:neural_canvas/services/auth_service.dart';
import 'package:neural_canvas/main.dart';

class ShareReceiverService {
  static final ShareReceiverService _instance =
      ShareReceiverService._internal();
  factory ShareReceiverService() => _instance;
  ShareReceiverService._internal();

  StreamSubscription? _intentDataStreamSubscription;

  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (kIsWeb) return;

    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            _processSharedFiles(value, navigatorKey);
          },
          onError: (err) {
            if (kDebugMode)
              debugPrint("ReceiveSharingIntent MediaStream Error: $err");
          },
        );

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      _processSharedFiles(value, navigatorKey);
    });
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  void _showUnsupportedTypeDialog(BuildContext context, String fileType) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B), // Slate 800
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFA78BFA), size: 28),
              SizedBox(width: 12),
              Text(
                'Invalid File Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          content: Text(
            'Axiom cannot process files with the extension [ .$fileType ]. Please share eligible images, text notes, or PDFs.',
            style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF818CF8),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processSharedFiles(
    List<SharedMediaFile> files,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (files.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (var file in files) {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) continue;

      final path = file.path;
      String fileName = path.split('/').last;
      String ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

      final bool isEligibleImage =
          file.type == SharedMediaType.image ||
          ['jpg', 'jpeg', 'png', 'gif', 'heic', 'webp'].contains(ext);

      final bool isEligibleDoc = [
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
      ].contains(ext);

      // 1. Validate File Format Eligibility
      if (!isEligibleImage &&
          !isEligibleDoc &&
          file.type != SharedMediaType.text &&
          file.type != SharedMediaType.url) {
        _showUnsupportedTypeDialog(context, ext.toUpperCase());
        continue;
      }

      // 2. Validate Daily Upload Quotas Against Plan Tiers
      final bool quotaCleared = await AuthService.checkUserUploadQuota(
        context,
        user.uid,
      );
      if (!quotaCleared) return;

      // Instantly open the application view context straight to the Library Tab (Index 1)
      globalTabController.value = 1;

      AiProcessingType aiType = isEligibleImage ? AiProcessingType.image : (ext == 'pdf' ? AiProcessingType.pdf : AiProcessingType.text);

      // Trigger the global visual background AI processing shimmer overlay
      globalAiProcessingState.value = AiProcessingData(aiType);

      try {
        if (file.type == SharedMediaType.text ||
            file.type == SharedMediaType.url) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('knowledge_base')
              .add({
                'title': 'Shared Clip Note',
                'type': 'text',
                'content': path,
                'createdAt': FieldValue.serverTimestamp(),
                'uploadedAt': FieldValue.serverTimestamp(),
              });
        } else {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final storageRef = FirebaseStorage.instance.ref().child(
            'users/${user.uid}/knowledge_base/${timestamp}_$fileName',
          );

          final uploadTask = storageRef.putFile(File(path));
          final snapshot = await uploadTask;
          final mediaUrl = await snapshot.ref.getDownloadURL();

          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('knowledge_base')
              .doc();

          // Combined schema maps satisfy your internal local screens & cloud analyzers
          await docRef.set({
            'fileName': fileName,
            'title': isEligibleImage
                ? 'Shared Image Asset'
                : 'Shared Document Asset',
            'smartTitle': isEligibleImage
                ? 'Shared Image Asset'
                : 'Shared Document Asset',
            'type': isEligibleImage ? 'image' : 'document',
            'fileType': ext,
            'path': mediaUrl,
            'url': mediaUrl,
            'fileUrl': mediaUrl,
            'uploadedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'aiSummary': 'Processing data...',
          });

          // Hand off the valid web URL directly to your backend Gemini analyzer instance
          AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, ext);
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint("Error executing share intent cloud ingest: $e");
      }

      globalAiProcessingState.value = null;
    }
  }
}
