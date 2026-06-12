import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildFileIcon(String fileType, String fileUrl) {
    if (fileType == 'png' || fileType == 'jpeg' || fileType == 'jpg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: fileUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 48,
            height: 48,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          errorWidget: (context, url, error) => Container(
            width: 48,
            height: 48,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_not_supported, size: 24),
          ),
        ),
      );
    }
    
    IconData iconData;
    Color iconColor;

    if (fileType == 'pdf') {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.redAccent;
    } else if (fileType == 'mp3' || fileType == 'm4a' || fileType == 'wav') {
      iconData = Icons.graphic_eq;
      iconColor = Colors.deepPurpleAccent;
    } else if (fileType == 'doc' || fileType == 'docx' || fileType == 'txt') {
      iconData = Icons.description;
      iconColor = Colors.blueAccent;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor, size: 28),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Text('Please sign in to view your Library.', style: TextStyle(color: cs.onSurface)),
        ),
      );
    }

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
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: cs.primary.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: 2),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search your assets...',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 15),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.search, size: 22, color: cs.primary),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.mic_none, size: 22, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Stream Builder List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('knowledge_base')
                    .orderBy('uploadedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading library.', style: TextStyle(color: cs.onSurface)));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  
                  // Local Filtering
                  final filteredDocs = docs.where((doc) {
                    if (_searchQuery.isEmpty) return true;
                    final data = doc.data() as Map<String, dynamic>;
                    final fileName = (data['fileName'] ?? '').toString().toLowerCase();
                    final aiSummary = (data['aiSummary'] ?? '').toString().toLowerCase();
                    return fileName.contains(_searchQuery) || aiSummary.contains(_searchQuery);
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            docs.isEmpty ? 'Your library is empty' : 'No matching assets found',
                            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final data = filteredDocs[index].data() as Map<String, dynamic>;
                      final fileName = data['fileName'] ?? 'Untitled';
                      final fileType = data['fileType'] ?? 'unknown';
                      final fileUrl = data['fileUrl'] ?? '';
                      final aiSummary = data['aiSummary'] ?? 'Processing data...';
                      final uploadedAt = data['uploadedAt'] as Timestamp?;
                      
                      String dateStr = '';
                      if (uploadedAt != null) {
                        final date = uploadedAt.toDate();
                        dateStr = "${date.month}/${date.day}/${date.year}";
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening $fileName...')));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  _buildFileIcon(fileType, fileUrl),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileName,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          aiSummary,
                                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      dateStr, 
                                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5))
                                    ),
                                  ],
                                ],
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
