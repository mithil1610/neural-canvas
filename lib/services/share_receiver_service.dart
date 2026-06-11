import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:neural_canvas/services/decomposition_service.dart';
import 'package:neural_canvas/widgets/ai_processing_overlay.dart';

class ShareReceiverService {
  // Singleton pattern
  static final ShareReceiverService _instance = ShareReceiverService._internal();
  factory ShareReceiverService() => _instance;
  ShareReceiverService._internal();

  StreamSubscription? _intentDataStreamSubscription;
  final DecompositionService _decompositionService = DecompositionService();

  void initialize(GlobalKey<NavigatorState> navigatorKey) {
    if (kIsWeb) return; // Web does not support receive_sharing_intent
    // 1. For handling media files shared while the app is already open in the background.
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _processSharedFiles(value, navigatorKey);
    }, onError: (err) {
      debugPrint("ReceiveSharingIntent MediaStream Error: $err");
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

    for (var file in files) {
      final path = file.path;

      String fileType = 'unknown';
      AiProcessingType aiType = AiProcessingType.unknown;

      if (file.type == SharedMediaType.image) {
        fileType = 'image';
        aiType = AiProcessingType.image;
      } else if (file.type == SharedMediaType.video) {
        fileType = 'video';
        aiType = AiProcessingType.video;
      } else if (file.type == SharedMediaType.file) {
        if (path.toLowerCase().endsWith('.pdf')) {
          fileType = 'pdf';
          aiType = AiProcessingType.pdf;
        } else {
          fileType = 'document';
          aiType = AiProcessingType.text;
        }
      } else if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        fileType = 'text';
        aiType = AiProcessingType.text;
      }

      // Activate the global overlay immediately before processing
      globalAiProcessingState.value = AiProcessingData(aiType);

      try {
        final analysis = await _decompositionService.analyzeSharedAsset(
          filePath: path,
          fileType: fileType,
        );
        debugPrint("Analysis completed for $path: $analysis");
      } catch (e) {
        debugPrint("Error analyzing shared asset: $e");
      }
      
      // Deactivate immediately when finished
      globalAiProcessingState.value = null;
    }
  }
}
