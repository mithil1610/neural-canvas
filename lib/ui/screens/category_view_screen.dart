import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CategoryViewScreen extends StatefulWidget {
  final String selectedCategory;

  const CategoryViewScreen({super.key, required this.selectedCategory});

  @override
  State<CategoryViewScreen> createState() => _CategoryViewScreenState();
}

class _CategoryViewScreenState extends State<CategoryViewScreen> {
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
            color: Colors.white10,
            child: const Icon(Icons.image, size: 24),
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

    if (fileType == 'pdf' || fileType == 'docx' || fileType == 'txt') {
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
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      ),
      child: Icon(iconData, color: iconColor, size: size * 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.selectedCategory.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(child: Text("Authentication required"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('knowledge_base')
                  .where(
                    'category',
                    '==',
                    widget.selectedCategory.toLowerCase(),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTime = aData['uploadedAt'] as Timestamp?;
                  final bTime = bData['uploadedAt'] as Timestamp?;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.category_outlined,
                          size: 64,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No assets in ${widget.selectedCategory}",
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final smartTitle =
                        data['smartTitle'] ?? data['fileName'] ?? 'Untitled';
                    final fileType = data['fileType'] ?? 'unknown';
                    final fileUrl = data['fileUrl'] ?? '';
                    final timestamp = data['uploadedAt'] as Timestamp?;
                    final dateStr = timestamp != null
                        ? "${timestamp.toDate().year}-${timestamp.toDate().month.toString().padLeft(2, '0')}-${timestamp.toDate().day.toString().padLeft(2, '0')}"
                        : 'Unknown Date';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: _buildFileIcon(fileType, fileUrl, size: 48),
                        title: Text(
                          smartTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
