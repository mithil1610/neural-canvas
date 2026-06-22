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
import 'package:neural_canvas/main.dart';

class ShareReceiverService {
  // Singleton pattern
  static final ShareReceiverService _instance = ShareReceiverService._internal();
  factory ShareReceiverService() => _instance;
  ShareReceiverService._internal();

  StreamSubscription? _intentDataStreamSubscription;

  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (kIsWeb) return; // Web does not support receive_sharing_intent
    // 1. For handling media files shared while the app is already open in the background.
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _processSharedFiles(value, navigatorKey);
    }, onError: (err) {
      if (kDebugMode) debugPrint("ReceiveSharingIntent MediaStream Error: $err");
    });

    // 2. For handling media files shared while the app was completely closed (cold start).
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _processSharedFiles(value, navigatorKey);
    });
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  Future<void> _processSharedFiles(List<SharedMediaFile> files, GlobalKey<NavigatorState> navigatorKey) async {
    if (files.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (var file in files) {
      final path = file.path;

      // Extract file name and extension
      String fileName = path.split('/').last;
      String ext = 'unknown';
      if (fileName.contains('.')) {
        ext = fileName.split('.').last.toLowerCase();
      }

      AiProcessingType aiType = AiProcessingType.unknown;

      if (file.type == SharedMediaType.image) {
        aiType = AiProcessingType.image;
      } else if (file.type == SharedMediaType.video) {
        aiType = AiProcessingType.video;
      } else if (file.type == SharedMediaType.file) {
        if (ext == 'pdf') {
          aiType = AiProcessingType.pdf;
        } else {
          aiType = AiProcessingType.text;
        }
      } else if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        aiType = AiProcessingType.text;
      }

      // Transition user immediately to Knowledge Base Tab (Index 1)
      globalTabController.value = 1;

      // Activate the global overlay immediately before processing
      globalAiProcessingState.value = AiProcessingData(aiType);

      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users/${user.uid}/knowledge_base/${timestamp}_$fileName');

        final uploadTask = storageRef.putFile(File(path));
        final snapshot = await uploadTask;
        final mediaUrl = await snapshot.ref.getDownloadURL();

        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('knowledge_base')
            .doc();

        await docRef.set({
          'fileName': fileName,
          'fileUrl': mediaUrl,
          'fileType': ext,
          'uploadedAt': FieldValue.serverTimestamp(),
          'aiSummary': 'Processing data...',
        });
        
        // Fire the asynchronous analyzer immediately
        AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, ext);
        
        if (kDebugMode) debugPrint("Share intent upload completed for $fileName");
      } catch (e) {
        if (kDebugMode) debugPrint("Error analyzing shared asset: $e");
      }
      
      // Deactivate immediately when finished
      globalAiProcessingState.value = null;
    }
  }
}
