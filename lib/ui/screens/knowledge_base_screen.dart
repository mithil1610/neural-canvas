import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import '../../utils/ui_utils.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final TextEditingController _searchController = TextEditingController();
  // Search and filter variables
  String _selectedFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    setState(() {});
  }

  Widget _buildFileIcon(String fileType, String fileUrl, {double size = 48}) {
    if (fileType == 'png' || fileType == 'jpeg' || fileType == 'jpg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor, size: size * 0.6),
    );
  }

  void _showDetailModal(
    BuildContext context,
    String currentDocId,
    String smartTitle,
    String fileType,
    String fileUrl,
    String aiSummary,
    List<QueryDocumentSnapshot> allDocs,
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
                                smartTitle,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 40, color: Colors.white24),
                        const Text(
                          "CONNECTED MEMORY GRAPH",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 100,
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                .collection('knowledge_base')
                                .where(
                                  FieldPath.documentId,
                                  isNotEqualTo: currentDocId,
                                )
                                .limit(6)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white24,
                                  ),
                                );
                              }
                              if (snapshot.hasError ||
                                  !snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "Isolating node... Upload more assets to discover automated contextual connections.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final docs = snapshot.data!.docs;
                              return ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final cDoc = docs[index];
                                  final cData =
                                      cDoc.data() as Map<String, dynamic>;
                                  final cName =
                                      cData['smartTitle'] ??
                                      cData['fileName'] ??
                                      'Untitled';
                                  final cType = cData['fileType'] ?? 'unknown';
                                  final cUrl = cData['fileUrl'] ?? '';
                                  final cSummary = cData['aiSummary'] ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.pop(context);
                                        _showDetailModal(
                                          context,
                                          cDoc.id,
                                          cName,
                                          cType,
                                          cUrl,
                                          cSummary,
                                          allDocs,
                                        );
                                      },
                                      child: Container(
                                        width: 90,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _buildFileIcon(
                                              cType,
                                              cUrl,
                                              size: 40,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              cName,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: cs.onSurfaceVariant,
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
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
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

  Future<void> _deleteAsset(String docId, String fileUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (fileUrl.isNotEmpty) {
        await FirebaseStorage.instance.refFromURL(fileUrl).delete();
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('knowledge_base')
          .doc(docId)
          .delete();

      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Asset deleted');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Failed to delete asset: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Text(
            'Please sign in to view your Library.',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      );
    }

    // Build the unconstrained query
    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('knowledge_base')
        .orderBy('uploadedAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Text(
                'Library',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: _performSearch,
                  onChanged: _performSearch,
                  decoration: InputDecoration(
                    hintText: "Search your library...",
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.search, size: 22, color: cs.primary),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _searchController.clear();
                              _performSearch('');
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(
                              Icons.mic_none,
                              size: 22,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Filter Chips Row
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: ['All', 'Documents', 'Images', 'Audio', 'Video'].map((
                  filter,
                ) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = filter;
                        });
                      },
                      backgroundColor: cs.surfaceContainerHighest,
                      selectedColor: cs.primaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Stream Builder List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: query.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading library.',
                        style: TextStyle(color: cs.onSurface),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allDocs = snapshot.data?.docs ?? [];

                  // Local Filtering
                  final filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    // Chip filter
                    final type = (data['fileType'] ?? '')
                        .toString()
                        .toLowerCase();
                    bool chipMatches = true;
                    if (_selectedFilter == "Images") {
                      chipMatches = ['png', 'jpg', 'jpeg'].contains(type);
                    } else if (_selectedFilter == "Documents") {
                      chipMatches = [
                        'pdf',
                        'doc',
                        'docx',
                        'txt',
                      ].contains(type);
                    } else if (_selectedFilter == "Audio") {
                      chipMatches = ['mp3', 'm4a', 'wav'].contains(type);
                    } else if (_selectedFilter == "Video") {
                      chipMatches = ['mp4', 'mov'].contains(type);
                    }

                    if (!chipMatches) return false;

                    // Search filter
                    final queryText = _searchController.text.trim().toLowerCase();
                    if (queryText.isNotEmpty) {
                      final title = (data['smartTitle'] ?? '').toString().toLowerCase();
                      final fileName = (data['fileName'] ?? '').toString().toLowerCase();
                      final summary = (data['aiSummary'] ?? '').toString().toLowerCase();
                      if (!title.contains(queryText) &&
                          !fileName.contains(queryText) &&
                          !summary.contains(queryText)) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            allDocs.isEmpty
                                ? 'Your library is empty'
                                : 'No matching assets found',
                            style: TextStyle(
                              fontSize: 16,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final docId = filteredDocs[index].id;
                      final data =
                          filteredDocs[index].data() as Map<String, dynamic>;
                      final fileName = data['fileName'] ?? 'Untitled';
                      final smartTitle = data['smartTitle'] ?? fileName;
                      final fileType = data['fileType'] ?? 'unknown';
                      final fileUrl = data['fileUrl'] ?? '';
                      final aiSummary =
                          data['aiSummary'] ?? 'Processing data...';
                      final uploadedAt = data['uploadedAt'] as Timestamp?;

                      String dateStr = '';
                      if (uploadedAt != null) {
                        final date = uploadedAt.toDate();
                        dateStr = "${date.month}/${date.day}/${date.year}";
                      }

                      return Dismissible(
                        key: Key(docId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.shade700,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        onDismissed: (_) {
                          _deleteAsset(docId, fileUrl);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.2),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _showDetailModal(
                                  context,
                                  docId,
                                  smartTitle,
                                  fileType,
                                  fileUrl,
                                  aiSummary,
                                  allDocs,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    _buildFileIcon(fileType, fileUrl, size: 56),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            smartTitle,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (dateStr.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: cs.onSurfaceVariant
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            aiSummary,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant
                                                  .withValues(alpha: 0.8),
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: cs.onSurfaceVariant.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
