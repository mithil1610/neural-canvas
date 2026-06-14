import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:neural_canvas/ui/screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:neural_canvas/services/asset_analyzer_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class QuickAction {
  final IconData icon;
  final String label;
  final Color color;

  const QuickAction({required this.icon, required this.label, required this.color});
}

const List<QuickAction> _quickActions = [
  QuickAction(icon: Icons.camera_alt_outlined, label: 'Scan', color: Color(0xFF818CF8)),
  QuickAction(icon: Icons.mic_none, label: 'Voice Note', color: Color(0xFFA78BFA)),
  QuickAction(icon: Icons.upload_file_outlined, label: 'Import', color: Color(0xFF0EA5E9)),
  QuickAction(icon: Icons.auto_awesome, label: 'Generate', color: Color(0xFFF59E0B)),
];

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _isImporting = false;
  bool _isRecording = false;
  final _audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning ☀️';
    if (hour < 17) return 'Good afternoon 🌤️';
    return 'Good evening 🌙';
  }

  // Generate dynamic title from AI summary
  String _generateReelTitle(String aiSummary, String fallbackType) {
    final summaryLower = aiSummary.toLowerCase();
    if (summaryLower.contains("receipt") || summaryLower.contains("invoice") || summaryLower.contains("financial")) return "Financial Records";
    if (summaryLower.contains("route") || summaryLower.contains("run") || summaryLower.contains("workout")) return "Fitness Highlights";
    if (summaryLower.contains("vacation") || summaryLower.contains("trip") || summaryLower.contains("travel")) return "Travel Memories";
    if (summaryLower.contains("design") || summaryLower.contains("meeting") || summaryLower.contains("work")) return "Work Insights";
    if (summaryLower.contains("recipe") || summaryLower.contains("cook") || summaryLower.contains("food")) return "Culinary Collection";
    
    // Extracted fileType fallback
    if (fallbackType == 'pdf' || fallbackType == 'doc' || fallbackType == 'docx') return "Document Insights";
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
            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
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

    if (fileType == 'pdf' || fileType == 'doc' || fileType == 'docx' || fileType == 'txt') {
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

  void _showDetailModal(BuildContext context, String fileName, String fileType, String fileUrl, String aiSummary) {
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
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
                                fileName,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.2), height: 1),
                  
                  // AI Summary Content
                  Expanded(
                    child: Markdown(
                      data: aiSummary,
                      padding: const EdgeInsets.all(24),
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontSize: 16, color: cs.onSurface, height: 1.6),
                        h1: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.primary),
                        h2: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface),
                        h3: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
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
    if (_isImporting) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() { _isImporting = true; });

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = file.name;
      final storageRef = FirebaseStorage.instance.ref().child('users/${user.uid}/knowledge_base/${timestamp}_$fileName');

      UploadTask uploadTask;
      if (kIsWeb) {
        uploadTask = storageRef.putData(file.bytes!);
      } else {
        uploadTask = storageRef.putFile(File(file.path!));
      }

      final snapshot = await uploadTask;
      final mediaUrl = await snapshot.ref.getDownloadURL();
      final ext = file.extension?.toLowerCase() ?? 'unknown';

      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('knowledge_base').doc();
      await docRef.set({
        'fileName': fileName,
        'fileUrl': mediaUrl,
        'fileType': ext,
        'uploadedAt': FieldValue.serverTimestamp(),
        'aiSummary': 'Processing data...',
      });

      AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, ext);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset successfully ingested!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() { _isImporting = false; });
    }
  }

  Future<void> _handleScan() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() { _isImporting = true; });

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = image.name;
      final storageRef = FirebaseStorage.instance.ref().child('users/${user.uid}/knowledge_base/${timestamp}_$fileName');

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

      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('knowledge_base').doc();
      await docRef.set({
        'fileName': 'Camera Capture',
        'fileUrl': mediaUrl,
        'fileType': ext,
        'uploadedAt': FieldValue.serverTimestamp(),
        'aiSummary': 'Processing image data...',
      });

      AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, ext);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan successfully ingested!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    } finally {
      if (mounted) setState(() { _isImporting = false; });
    }
  }

  Future<void> _handleVoiceNote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
        final String filePath = '${appDocumentsDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), // m4a/aac container
          path: filePath,
        );
        setState(() { _isRecording = true; });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text('Recording Voice Note...', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      Navigator.pop(context); // Close dialog
                      final path = await _audioRecorder.stop();
                      setState(() { _isRecording = false; _isImporting = true; });

                      if (path != null) {
                        final file = File(path);
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = 'VoiceNote_$timestamp.m4a';
                        final storageRef = FirebaseStorage.instance.ref().child('users/${user.uid}/knowledge_base/$fileName');
                        
                        final uploadTask = storageRef.putFile(file);
                        final snapshot = await uploadTask;
                        final mediaUrl = await snapshot.ref.getDownloadURL();
                        
                        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('knowledge_base').doc();
                        await docRef.set({
                          'fileName': 'Voice Note',
                          'fileUrl': mediaUrl,
                          'fileType': 'm4a',
                          'uploadedAt': FieldValue.serverTimestamp(),
                          'aiSummary': 'Transcribing audio...',
                        });

                        AssetAnalyzerService.analyzeIngestedAsset(docRef.id, mediaUrl, 'm4a');

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice note ingested!')));
                        }
                      }
                      if (mounted) setState(() { _isImporting = false; });
                    },
                    child: const Text('Stop & Save'),
                  ),
                ],
              ),
            ),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied.')));
      }
    } catch (e) {
      if (mounted) setState(() { _isRecording = false; _isImporting = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recording failed: $e')));
    }
  }

  Widget _buildQuickAction(BuildContext context, QuickAction action) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (action.label == 'Import') _handleImport();
              if (action.label == 'Scan') _handleScan();
              if (action.label == 'Voice Note') _handleVoiceNote();
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: action.color.withValues(alpha: 0.3)),
              ),
              child: ((_isImporting && (action.label == 'Import' || action.label == 'Scan' || action.label == 'Voice Note')) || (_isRecording && action.label == 'Voice Note'))
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2, color: action.color),
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
              title: const Text('Neural Canvas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.5)),
              actions: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))
                        .then((_) { if (mounted) setState(() {}); });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: StreamBuilder<User?>(
                      stream: FirebaseAuth.instance.userChanges(),
                      builder: (context, snapshot) {
                        final u = snapshot.data ?? FirebaseAuth.instance.currentUser;
                        return CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.surfaceContainerHighest,
                          backgroundImage: u?.photoURL != null ? CachedNetworkImageProvider(u!.photoURL!) : null,
                          child: u?.photoURL == null ? Icon(Icons.person, size: 20, color: cs.onSurfaceVariant) : null,
                        );
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: Stack(
                    children: [
                      const Icon(Icons.notifications_none_rounded),
                      Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle))),
                    ],
                  ),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
              ],
            ),

            // --- Greeting ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_getGreeting(), style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Your memory stream is active.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ),

            // --- Quick Actions ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _quickActions.map((action) => _buildQuickAction(context, action)).toList(),
                ),
              ),
            ),

            // --- Memory Reels Feed ---
            if (user == null)
              const SliverToBoxAdapter(child: Center(child: Text("Sign in to view Memory Reels.")))
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('knowledge_base')
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const SliverToBoxAdapter(child: Center(child: Text('Error loading feed.')));
                  if (!snapshot.hasData) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));

                  final allDocs = snapshot.data!.docs;
                  if (allDocs.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(child: Text("Your memory vault is empty.", style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)))),
                      ),
                    );
                  }

                  // Cluster logic
                  Map<String, List<QueryDocumentSnapshot>> clusters = {};
                  for (var doc in allDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final ts = data['uploadedAt'] as Timestamp?;
                    if (ts == null) continue;
                    final d = ts.toDate();
                    final key = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
                    if (!clusters.containsKey(key)) clusters[key] = [];
                    clusters[key]!.add(doc);
                  }

                  final clusterKeys = clusters.keys.toList()..sort((a, b) => b.compareTo(a));

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final dateKey = clusterKeys[index];
                        final items = clusters[dateKey]!;
                        final firstData = items.first.data() as Map<String, dynamic>;
                        
                        final dynamicTitle = _generateReelTitle(
                          (firstData['aiSummary'] ?? '').toString(),
                          (firstData['fileType'] ?? '').toString(),
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dynamicTitle,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                                  ),
                                  Text(
                                    "${items.length} items",
                                    style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 140,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: items.length,
                                itemBuilder: (context, i) {
                                  final doc = items[i];
                                  final data = doc.data() as Map<String, dynamic>;
                                  final fileType = data['fileType'] ?? 'unknown';
                                  final fileUrl = data['fileUrl'] ?? '';
                                  final fileName = data['fileName'] ?? 'Asset';
                                  final aiSummary = data['aiSummary'] ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () {
                                          _showDetailModal(context, fileName, fileType, fileUrl, aiSummary);
                                        },
                                        child: Container(
                                          width: 140,
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              _buildFileIcon(fileType, fileUrl, size: 80),
                                              const SizedBox(height: 8),
                                              Text(
                                                fileName,
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                      childCount: clusterKeys.length,
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
}
