import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:neural_canvas/ui/screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:neural_canvas/services/asset_analyzer_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:lottie/lottie.dart';
import '../../utils/ui_utils.dart';
import '../../services/user_service.dart';
import '../../services/auth_service.dart';
import '../modals/paywall_sheet.dart';

import '../screens/chronos_matrix_screen.dart';
import '../screens/cinematic_reel_screen.dart';
import '../screens/visual_lookbook_screen.dart';
import '../../utils/privacy_helper.dart';

class QuickAction {
  final IconData icon;
  final String label;
  final Color color;

  const QuickAction({
    required this.icon,
    required this.label,
    required this.color,
  });
}

const List<QuickAction> _quickActions = [
  QuickAction(
    icon: Icons.camera_alt_outlined,
    label: 'Scan',
    color: Color(0xFF818CF8),
  ),
  QuickAction(
    icon: Icons.mic_none,
    label: 'Voice Note',
    color: Color(0xFFA78BFA),
  ),
  QuickAction(
    icon: Icons.upload_file_outlined,
    label: 'Import',
    color: Color(0xFF0EA5E9),
  ),
  QuickAction(
    icon: Icons.auto_awesome,
    label: 'Generate',
    color: Color(0xFFF59E0B),
  ),
  QuickAction(
    icon: Icons.paste_outlined,
    label: 'Paste Text',
    color: Color(0xFF10B981),
  ),
];

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  String? activeLoadingAction;
  final _audioRecorder = AudioRecorder();
  bool hasUnreadNotifications = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCompliance();
    });
  }

  Future<void> _checkCompliance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && !data.containsKey('legalCompliance')) {
          if (!mounted) return;
          _showLegacyComplianceModal();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Compliance check error: $e");
    }
  }

  void _showLegacyComplianceModal() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.5,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.02),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Neural Matrix Alignment',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        "We have updated our Terms of Service and Privacy Policy to guarantee absolute transparency. By continuing into your Second Brain, you authorize secure data indexing executed strictly via our dedicated Google Gemini API infrastructure. Your uploaded assets are fully encrypted, protected from public model training cycles, and remain completely sovereign to you.",
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .set({
                              'legalCompliance': {
                                'agreedToTermsAndPrivacy': true,
                                'consentTimestamp':
                                    FieldValue.serverTimestamp(),
                                'regulatoryScope': 'Global_v1',
                              },
                            }, SetOptions(merge: true));
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Synchronize Matrix'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _getGreeting([String? name]) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    if (name != null && name.trim().isNotEmpty) {
      final firstName = name.trim().split(' ').first;
      return '$greeting, $firstName';
    }
    return greeting;
  }

  // Generate dynamic title from AI summary
  String _generateReelTitle(String aiSummary, String fallbackType) {
    final summaryLower = aiSummary.toLowerCase();
    if (summaryLower.contains("receipt") ||
        summaryLower.contains("invoice") ||
        summaryLower.contains("financial")) {
      return "Financial Records";
    }
    if (summaryLower.contains("route") ||
        summaryLower.contains("run") ||
        summaryLower.contains("workout")) {
      return "Fitness Highlights";
    }
    if (summaryLower.contains("vacation") ||
        summaryLower.contains("trip") ||
        summaryLower.contains("travel")) {
      return "Travel Memories";
    }
    if (summaryLower.contains("design") ||
        summaryLower.contains("meeting") ||
        summaryLower.contains("work")) {
      return "Work Insights";
    }
    if (summaryLower.contains("recipe") ||
        summaryLower.contains("cook") ||
        summaryLower.contains("food")) {
      return "Culinary Collection";
    }

    // Extracted fileType fallback
    if (fallbackType == 'pdf' ||
        fallbackType == 'doc' ||
        fallbackType == 'docx') {
      return "Document Insights";
    }
    if (fallbackType == 'mp4' || fallbackType == 'mov') return "Video Timeline";
    if (fallbackType == 'mp3' || fallbackType == 'wav') return "Audio Captures";

    return "Visual Musings";
  }

  Widget _buildFileIcon(String fileType, String fileUrl, {double size = 48}) {
    if (fileType == 'png' || fileType == 'jpeg' || fileType == 'jpg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: fileUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_not_supported, size: 24),
          ),
        ),
      );
    }

    IconData iconData;
    Color iconColor;

    if (fileType == 'pdf' ||
        fileType == 'doc' ||
        fileType == 'docx' ||
        fileType == 'txt') {
      iconData = fileType == 'pdf' ? Icons.picture_as_pdf : Icons.description;
      iconColor = fileType == 'pdf' ? Colors.redAccent : Colors.blueAccent;
    } else if (fileType == 'mp3' || fileType == 'm4a' || fileType == 'wav') {
      iconData = Icons.graphic_eq;
      iconColor = Colors.deepPurpleAccent;
    } else if (fileType == 'mp4' || fileType == 'mov') {
      iconData = Icons.video_library;
      iconColor = Colors.orangeAccent;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(iconData, color: iconColor, size: size * 0.5),
    );
  }

  void _showDetailModal(
    BuildContext context,
    String title,
    String fileType,
    String fileUrl,
    String aiSummary,
  ) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.02),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header / File Preview
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildFileIcon(fileType, fileUrl, size: 64),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    fileType.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                    height: 1,
                  ),

                  // AI Summary Content
                  Expanded(
                    child: Markdown(
                      data: aiSummary,
                      padding: const EdgeInsets.all(24),
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 16,
                          color: cs.onSurface,
                          height: 1.6,
                        ),
                        h1: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        h2: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                        h3: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        listBullet: TextStyle(color: cs.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleImport() async {
    bool consentGranted = await PrivacyHelper.ensureAIConsent(context);
    if (!consentGranted) return;
    if (activeLoadingAction != null) return;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (BuildContext ctx) {
        return Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF111114),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Ingest New Knowledge",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white70),
                title: const Text(
                  "📸 Photo & Screenshot Library",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _processImport(source: 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_copy, color: Colors.white70),
                title: const Text(
                  "📁 Browse Text Files & PDFs",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _processImport(source: 'file');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processImport({required String source}) async {
    if (!mounted) return;

    try {
      List<String> filePaths = [];
      List<String> fileNames = [];

      if (source == 'photo') {
        final ImagePicker picker = ImagePicker();
        final List<XFile> images = await picker.pickMultiImage(
          imageQuality: 75,
          maxWidth: 1920,
          maxHeight: 1080,
        );
        if (images.isEmpty) return;

        List<XFile> pickedFiles = images;
        if (pickedFiles.length > 10) {
          if (mounted) {
            UIUtils.showFloatingSnackBar(
              context,
              'Maximum allocation threshold exceeded. Only the first 10 selected files will be processed.',
            );
          }
          pickedFiles = pickedFiles.take(10).toList();
        }

        filePaths = pickedFiles.map((e) => e.path).toList();
        fileNames = pickedFiles.map((e) => e.name).toList();
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: true,
          allowedExtensions: ['pdf', 'txt', 'docx'],
        );
        if (result == null || result.files.isEmpty) return;

        var pickedFiles = result.files;
        if (pickedFiles.length > 10) {
          if (mounted) {
            UIUtils.showFloatingSnackBar(
              context,
              'Maximum allocation threshold exceeded. Only the first 10 selected files will be processed.',
            );
          }
          pickedFiles = pickedFiles.take(10).toList();
        }

        filePaths = pickedFiles.map((e) => e.path!).toList();
        fileNames = pickedFiles.map((e) => e.name).toList();
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      bool isPremium = await UserService.isUserPremium(user.uid);

      setState(() {
        activeLoadingAction = 'import';
      });

      int successCount = 0;

      for (int i = 0; i < filePaths.length; i++) {
        if (!mounted) break;
        String filePath = filePaths[i];
        String fileName = fileNames[i];

        if (!await AuthService.checkAndIncrementUsage(context)) break;
        if (!mounted) break;
        if (!await AuthService.checkUserUploadQuota(context)) break;

        if (!isPremium) {
          final length = File(filePath).lengthSync();
          if (length > 5 * 1024 * 1024) {
            if (mounted) {
              UIUtils.showFloatingSnackBar(
                context,
                'Skipping $fileName: Free tier is limited to 5MB files.',
              );
            }
            continue;
          }
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = FirebaseStorage.instance.ref().child(
          'users/${user.uid}/knowledge_base/${timestamp}_$fileName',
        );

        UploadTask uploadTask;
        if (kIsWeb) {
          final bytes = await File(filePath).readAsBytes();
          uploadTask = storageRef.putData(bytes);
        } else {
          uploadTask = storageRef.putFile(File(filePath));
        }

        final snapshot = await uploadTask;
        final mediaUrl = await snapshot.ref.getDownloadURL();
        final ext = fileName.contains('.')
            ? fileName.split('.').last.toLowerCase()
            : 'unknown';

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

        try {
          await AssetAnalyzerService.analyzeIngestedAsset(
            docRef.id,
            mediaUrl,
            ext,
          );
          successCount++;
        } catch (e) {
          if (e.toString().contains('429')) {
            if (mounted) {
              UIUtils.showFloatingSnackBar(
                context,
                "Rate limit hit. Holding for 4 seconds...",
              );
            }
            await Future.delayed(const Duration(milliseconds: 4000));
            try {
              await AssetAnalyzerService.analyzeIngestedAsset(
                docRef.id,
                mediaUrl,
                ext,
              );
              successCount++;
            } catch (e2) {
              if (mounted) {
                UIUtils.showFloatingSnackBar(
                  context,
                  "Retry failed for $fileName",
                );
              }
            }
          } else {
            if (mounted) {
              UIUtils.showFloatingSnackBar(
                context,
                "Analysis failed for $fileName",
              );
            }
          }
        }

        await Future.delayed(const Duration(milliseconds: 1500));
      }

      if (mounted && successCount > 0) {
        UIUtils.showFloatingSnackBar(
          context,
          '$successCount asset(s) successfully ingested!',
        );
      }
    } catch (e) {
      if (mounted) UIUtils.showFloatingSnackBar(context, 'Import failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          activeLoadingAction = null;
        });
      }
    }
  }

  Future<void> _handleScan() async {
    bool consentGranted = await PrivacyHelper.ensureAIConsent(context);
    if (!consentGranted) return;
    if (!mounted) return;
    if (!await AuthService.checkAndIncrementUsage(context)) return;
    if (!mounted) return;
    if (!await AuthService.checkUserUploadQuota(context)) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (image == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() {
        activeLoadingAction = 'scan';
      });

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = image.name;
      final storageRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/knowledge_base/${timestamp}_$fileName',
      );

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = storageRef.putData(bytes);
      } else {
        uploadTask = storageRef.putFile(File(image.path));
      }

      final snapshot = await uploadTask;
      final mediaUrl = await snapshot.ref.getDownloadURL();
      final ext = 'jpg'; // force jpg for camera captures

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('knowledge_base')
          .doc();
      await docRef.set({
        'fileName': 'Camera Capture',
        'fileUrl': mediaUrl,
        'fileType': ext,
        'uploadedAt': FieldValue.serverTimestamp(),
        'aiSummary': 'Processing image data...',
      });

      // await AuthService.incrementDailyUploadQuota();

      AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, ext);

      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Scan successfully ingested!');
      }
    } catch (e) {
      if (mounted) UIUtils.showFloatingSnackBar(context, 'Scan failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          activeLoadingAction = null;
        });
      }
    }
  }

  Future<void> _handleVoiceNote() async {
    bool consentGranted = await PrivacyHelper.ensureAIConsent(context);
    if (!consentGranted) return;
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await AuthService.checkAndIncrementUsage(context)) return;
    if (!mounted) return;
    if (!await AuthService.checkUserUploadQuota(context)) return;
    if (!mounted) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final Directory appDocumentsDir =
            await getApplicationDocumentsDirectory();
        final String filePath =
            '${appDocumentsDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), // m4a/aac container
          path: filePath,
        );
        setState(() {
          activeLoadingAction = 'voice';
        });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Recording Voice Note...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      Navigator.pop(dialogContext); // Close dialog
                      final path = await _audioRecorder.stop();
                      setState(() {
                        activeLoadingAction = 'voice';
                      });

                      if (path != null) {
                        final file = File(path);
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = 'VoiceNote_$timestamp.m4a';
                        final storageRef = FirebaseStorage.instance.ref().child(
                          'users/${user.uid}/knowledge_base/$fileName',
                        );

                        final uploadTask = storageRef.putFile(file);
                        final snapshot = await uploadTask;
                        final mediaUrl = await snapshot.ref.getDownloadURL();

                        final docRef = FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('knowledge_base')
                            .doc();
                        await docRef.set({
                          'fileName': 'Voice Note',
                          'fileUrl': mediaUrl,
                          'fileType': 'm4a',
                          'uploadedAt': FieldValue.serverTimestamp(),
                          'aiSummary': 'Transcribing audio...',
                        });

                        // await AuthService.incrementDailyUploadQuota();

                        AssetAnalyzerService.analyzeIngestedAsset(
                          docRef.id,
                          mediaUrl,
                          'm4a',
                        );

                        if (!mounted) return;
                        UIUtils.showFloatingSnackBar(
                          context,
                          'Voice note ingested!',
                        );
                      }
                      if (mounted) {
                        setState(() {
                          activeLoadingAction = null;
                        });
                      }
                    },
                    child: const Text('Stop & Save'),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          UIUtils.showFloatingSnackBar(
            context,
            'Microphone permission denied.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          activeLoadingAction = null;
        });
      }
      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Recording failed: $e');
      }
    }
  }

  Future<String> _generateTitleFromText(String text) async {
    const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiApiKey.isEmpty) {
      return 'Pasted_Note_${DateTime.now().millisecondsSinceEpoch}.txt';
    }
    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: geminiApiKey,
      );
      final prompt = "Review this pasted text snippet. Generate a highly descriptive, professional 3-to-4 word summary title. Return exclusively the raw title text string without any introductory phrases, wrap text, or punctuation marks. Text: ${text.substring(0, text.length > 500 ? 500 : text.length)}";
      final response = await model.generateContent([Content.text(prompt)]);
      final title = response.text?.trim() ?? 'Untitled Note';
      final sanitizedTitle = title.replaceAll('"', '').replaceAll('\n', ' ').trim();
      return '$sanitizedTitle.txt';
    } catch (e) {
      if (kDebugMode) debugPrint("Auto-titling failed: $e");
      return 'Pasted_Note_${DateTime.now().millisecondsSinceEpoch}.txt';
    }
  }

  Future<void> _handlePasteText() async {
    bool consentGranted = await PrivacyHelper.ensureAIConsent(context);
    if (!consentGranted) return;
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await AuthService.checkAndIncrementUsage(context)) return;
    if (!mounted) return;
    if (!await AuthService.checkUserUploadQuota(context)) return;
    if (!mounted) return;

    final TextEditingController textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Paste Text',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 8,
                minLines: 4,
                decoration: InputDecoration(
                  hintText: 'Paste or type your notes here...',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final rawText = textController.text.trim();
                    if (rawText.isEmpty) return;

                    Navigator.pop(sheetContext);
                    setState(() {
                      activeLoadingAction = 'paste';
                    });

                    try {
                      final docRef = FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('knowledge_base')
                          .doc();
                      final genTitle = await _generateTitleFromText(rawText);
                      await docRef.set({
                        'fileName': genTitle,
                        'fileUrl': '',
                        'fileType': 'text',
                        'uploadedAt': FieldValue.serverTimestamp(),
                        'aiSummary': rawText,
                      });

                      // await AuthService.incrementDailyUploadQuota();

                      if (mounted) {
                        UIUtils.showFloatingSnackBar(
                          context,
                          'Text note ingested! Enhancing...',
                        );
                      }

                      // Fire off background enhancement
                      _enhanceTextNode(docRef, rawText);
                    } catch (e) {
                      if (mounted) {
                        UIUtils.showFloatingSnackBar(
                          context,
                          'Failed to save text: $e',
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() {
                          activeLoadingAction = null;
                        });
                      }
                    }
                  },
                  child: const Text(
                    'Ingest Text Note',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Future<void> _enhanceTextNode(
    DocumentReference docRef,
    String rawText,
  ) async {
    const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiApiKey.isEmpty) return;

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey,
      );
      final prompt =
          "Analyze this raw text. Extract key themes and rewrite it into a highly optimized, structured summary. Return ONLY the summary.\n\nText: $rawText";
      final response = await model.generateContent([Content.text(prompt)]);

      if (response.text != null && response.text!.isNotEmpty) {
        await docRef.update({'aiSummary': response.text!.trim()});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to enhance text node: $e');
    }
  }

  Future<void> _handleGenerate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Premium Check Lock: Wired to actual user subscription data via utility layer
    bool isUserPremium = await UserService.isUserPremium(user.uid);

    if (!mounted) return;

    if (!isUserPremium) {
      // If the user's account flag is marked as a free account, present Paywall
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const PaywallSheet(),
      );
      return; // Stops the Generate engine from running
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: _GenerateDialog(user: user),
          ),
        );
      },
    );
  }

  Widget _buildQuickAction(BuildContext context, QuickAction action) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.lightImpact();
              if (action.label == 'Import') _handleImport();
              if (action.label == 'Scan') _handleScan();
              if (action.label == 'Voice Note') _handleVoiceNote();
              if (action.label == 'Generate') _handleGenerate();
              if (action.label == 'Paste Text') _handlePasteText();
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: action.color.withValues(alpha: 0.3)),
              ),
              child:
                  ((activeLoadingAction == 'import' &&
                          action.label == 'Import') ||
                      (activeLoadingAction == 'scan' &&
                          action.label == 'Scan') ||
                      (activeLoadingAction == 'voice' &&
                          action.label == 'Voice Note') ||
                      (activeLoadingAction == 'paste' &&
                          action.label == 'Paste Text'))
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: action.color,
                      ),
                    )
                  : Icon(action.icon, color: action.color, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          action.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            // --- App Bar ---
            SliverAppBar(
              floating: true,
              backgroundColor: cs.surface.withValues(alpha: 0.9),
              elevation: 0,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Axiom',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              actions: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: StreamBuilder<User?>(
                      stream: FirebaseAuth.instance.userChanges(),
                      builder: (context, snapshot) {
                        final u =
                            snapshot.data ?? FirebaseAuth.instance.currentUser;
                        return CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.surfaceContainerHighest,
                          backgroundImage: u?.photoURL != null
                              ? CachedNetworkImageProvider(u!.photoURL!)
                              : null,
                          child: u?.photoURL == null
                              ? Icon(
                                  Icons.person,
                                  size: 20,
                                  color: cs.onSurfaceVariant,
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      hasUnreadNotifications = false;
                    });
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      barrierColor: Colors.black.withValues(alpha: 0.5),
                      builder: (context) => Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF16161A),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "System Notifications",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 16),
                            ListTile(
                              leading: Icon(
                                Icons.bolt,
                                color: Colors.blueAccent,
                              ),
                              title: Text(
                                "Welcome to Axiom v1.1.2",
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                "Your AI bandwidth is fully charged and synchronized.",
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Stack(
                    children: [
                      const Icon(Icons.notifications_none_rounded),
                      if (hasUnreadNotifications)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),

            // --- Greeting ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseAuth.instance.currentUser != null
                      ? FirebaseFirestore.instance
                            .collection('users')
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .snapshots()
                      : null,
                  builder: (context, snapshot) {
                    String? name;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null) {
                        name =
                            data['fullName'] as String? ??
                            (data['email'] != null
                                ? data['email'].split('@')[0]
                                : 'Explorer');
                      }
                    }
                    name ??= FirebaseAuth.instance.currentUser?.displayName;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _getGreeting(name),
                              style: TextStyle(
                                fontSize: 15,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Lottie.network(
                              DateTime.now().hour < 17
                                  ? 'https://assets5.lottiefiles.com/packages/lf20_xlbhme96.json' // Day/Sun
                                  : 'https://assets10.lottiefiles.com/packages/lf20_isb7clby.json', // Moon/Night
                              width: 32,
                              height: 32,
                              animate: true,
                              repeat: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    DateTime.now().hour < 17 ? '☀️' : '🌙',
                                    style: const TextStyle(fontSize: 20),
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your memory stream is active.',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // --- Quick Actions ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _quickActions
                      .map((action) => _buildQuickAction(context, action))
                      .toList(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildVisualMusingsActionRow(context),
            ),

            // --- Upcoming Events Strip (Chronos Lens) ---
            if (user != null)
              SliverToBoxAdapter(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('upcoming_events')
                      .where(
                        'eventDateTime',
                        isGreaterThanOrEqualTo: DateTime.now()
                            .toIso8601String(),
                      )
                      .orderBy('eventDateTime', descending: false)
                      .limit(3)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const SizedBox(); // Hide if no events
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ChronosMatrixScreen(),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Upcoming Timeline Coordinates",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: snapshot.data!.docs.length,
                              itemBuilder: (context, index) {
                                final data =
                                    snapshot.data!.docs[index].data()
                                        as Map<String, dynamic>;
                                final title = data['eventTitle'] ?? 'Event';
                                final time = data['eventDateTime'] ?? 'TBD';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0EA5E9),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF0EA5E9,
                                              ).withValues(alpha: 0.5),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 14,
                                        color: Color(0xFF0EA5E9),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        time,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // --- Memory Reels Feed ---
            if (user == null)
              const SliverToBoxAdapter(
                child: Center(child: Text("Sign in to view Memory Reels.")),
              )
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('knowledge_base')
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const SliverToBoxAdapter(
                      child: Center(child: Text('Error loading feed.')),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  final allDocs = snapshot.data!.docs;
                  if (allDocs.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            "Your memory vault is empty.",
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  // Smart Grouping Buckets
                  Map<String, List<QueryDocumentSnapshot>> groupAClusters = {};
                  List<QueryDocumentSnapshot> groupB = [];
                  List<QueryDocumentSnapshot> groupC = [];

                  for (var doc in allDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final aiSummary = data['aiSummary']?.toString() ?? '';
                    final ts = data['uploadedAt'] as Timestamp?;

                    if (aiSummary == 'Analysis encountered an error.') {
                      groupC.add(doc);
                    } else if (ts == null) {
                      groupB.add(doc);
                    } else {
                      final d = ts.toDate();
                      final key =
                          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                      if (!groupAClusters.containsKey(key)) {
                        groupAClusters[key] = [];
                      }
                      groupAClusters[key]!.add(doc);
                    }
                  }

                  final clusterKeys = groupAClusters.keys.toList()
                    ..sort((a, b) => b.compareTo(a));

                  Widget buildAssetGrid(List<QueryDocumentSnapshot> items) {
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final doc = items[i];
                        final data = doc.data() as Map<String, dynamic>;
                        final fileType = data['fileType'] ?? 'unknown';
                        final fileUrl = data['fileUrl'] ?? '';
                        final fileName = data['fileName'] ?? 'Asset';
                        final smartTitle = data['smartTitle'] ?? fileName;
                        final aiSummary = data['aiSummary'] ?? '';

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _showDetailModal(
                                context,
                                smartTitle,
                                fileType,
                                fileUrl,
                                aiSummary,
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildFileIcon(fileType, fileUrl, size: 48),
                                  const SizedBox(height: 8),
                                  Text(
                                    smartTitle,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }

                  return SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group A
                        ...clusterKeys.map((dateKey) {
                          final items = groupAClusters[dateKey]!;
                          final firstData =
                              items.first.data() as Map<String, dynamic>;
                          final dynamicTitle = _generateReelTitle(
                            (firstData['aiSummary'] ?? '').toString(),
                            (firstData['fileType'] ?? '').toString(),
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  28,
                                  20,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dynamicTitle,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                              buildAssetGrid(items),
                            ],
                          );
                        }),

                        // Group B
                        if (groupB.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 32, 20, 16),
                            child: Text(
                              "Non-Dated Snapshots",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          buildAssetGrid(groupB),
                        ],

                        // Group C
                        if (groupC.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ExpansionTile(
                              collapsedBackgroundColor: cs.errorContainer
                                  .withValues(alpha: 0.1),
                              backgroundColor: cs.errorContainer.withValues(
                                alpha: 0.05,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              collapsedShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              leading: Icon(
                                Icons.warning_amber_rounded,
                                color: cs.error,
                              ),
                              title: Text(
                                "Unprocessed Vault (${groupC.length} assets)",
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              children: [
                                const SizedBox(height: 16),
                                buildAssetGrid(groupC),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  void showBlurUpsellOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.movie_creation_outlined,
                          size: 48,
                          color: Color(0xFFA78BFA),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "CINEMATIC RENDERING UNLOCKED",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Color(0xFFA78BFA),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Auto-Memory Reels utilize intensive cloud video composition engines. Upgrade to the Infinite Brain tier (\$49.99/mo) to unlock full-length cinematic video narrative production pipelines.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFA78BFA),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              // Simulate sandbox payment delay
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                              await Future.delayed(
                                const Duration(milliseconds: 1500),
                              );
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .set({
                                    'accountTier': 'premium',
                                  }, SetOptions(merge: true));
                              if (context.mounted) {
                                Navigator.of(context).pop(); // pop loading
                                Navigator.of(context).pop(); // pop overlay
                                UIUtils.showFloatingSnackBar(
                                  context,
                                  'Upgraded to Infinite Brain! Auto-Memory Reels unlocked.',
                                );
                              }
                            }
                          },
                          child: const Text(
                            "Upgrade to Infinite Brain",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          "Dismiss",
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVisualMusingsActionRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;
                final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                final accountTier = userDoc.data()?['accountTier'] ?? 'Free';
                
                if (accountTier != 'Infinite Brain') {
                  if (context.mounted) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const PaywallSheet(),
                    );
                  }
                } else {
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CinematicReelScreen()),
                    );
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.movie_creation_outlined, size: 16, color: Color(0xFFF59E0B)),
                    SizedBox(width: 6),
                    Text("Generate Cinematic Reel", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;
                final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                final accountTier = userDoc.data()?['accountTier'] ?? 'Free';
                
                if (accountTier != 'Infinite Brain') {
                  if (context.mounted) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const PaywallSheet(),
                    );
                  }
                } else {
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const VisualLookbookScreen()),
                    );
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome_mosaic_outlined, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 6),
                    Text("Launch Visual Lookbook", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    }
}
  
class _GenerateDialog extends StatefulWidget {
  final User user;
  const _GenerateDialog({required this.user});

  @override
  State<_GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends State<_GenerateDialog> {
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  String _generatedContent = '';
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  Future<void> _synthesizeMatrix() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _generatedContent = '';
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('knowledge_base')
          .get();

      String allSummaries = snapshot.docs
          .map((d) {
            final data = d.data();
            return "Asset: ${data['fileName']} | Summary: ${data['aiSummary']}";
          })
          .join('\n\n');

      final systemInstruction =
          "You are the Axiom Creation Engine. Review this complete vault of user-ingested knowledge memories: [VAULT: $allSummaries]. Based entirely on these personal records, fulfill the user's creative generation request: $prompt. Build an emotionally engaging, structurally sound narrative story arc or compilation response. Deliver the result in beautiful markdown styling.";

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
      );

      final responseStream = model.generateContentStream([
        Content.text(systemInstruction),
      ]);

      await for (final chunk in responseStream) {
        if (chunk.text != null) {
          if (mounted) {
            setState(() {
              _generatedContent += chunk.text!;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generatedContent = 'Error during synthesis: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Creation Engine',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              if (_generatedContent.isEmpty && !_isGenerating) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    controller: _promptController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          "What should your Second Brain create today? (e.g., 'Summarize my week', 'Draft an article from my notes')",
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text(
                      'Synthesize Matrix',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _synthesizeMatrix();
                    },
                  ),
                ),
              ] else if (_isGenerating && _generatedContent.isEmpty) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: cs.primary),
                        const SizedBox(height: 24),
                        const Text(
                          'Scanning knowledge coordinates...',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Engineering story arc...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: Markdown(
                    data: _generatedContent,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 15,
                        color: cs.onSurface,
                        height: 1.5,
                      ),
                      h1: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                      h2: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                      listBullet: TextStyle(color: cs.primary),
                    ),
                  ),
                ),
                if (!_isGenerating)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _generatedContent),
                            );
                            if (context.mounted) {
                              UIUtils.showFloatingSnackBar(
                                context,
                                'Copied securely to clipboard!',
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy Text'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            // ignore: deprecated_member_use
                            await Share.share(
                              _generatedContent,
                              subject: 'My Axiom Insight',
                            );
                          },
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Share Narrative'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
