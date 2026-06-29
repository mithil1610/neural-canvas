import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VisualLookbookScreen extends StatefulWidget {
  const VisualLookbookScreen({Key? key}) : super(key: key);

  @override
  State<VisualLookbookScreen> createState() => _VisualLookbookScreenState();
}

class _VisualLookbookScreenState extends State<VisualLookbookScreen> {
  List<DocumentSnapshot> _imageDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('knowledge_base')
          .orderBy('uploadedAt', descending: true)
          .get();

      setState(() {
        _imageDocs = snapshot.docs.where((doc) {
          final type = doc['fileType'] as String? ?? '';
          return type == 'png' || type == 'jpg' || type == 'jpeg';
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Visual Lookbook")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_imageDocs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Visual Lookbook")),
        body: const Center(
          child: Text("No visual assets found in your knowledge base."),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Visual Lookbook"),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: PageController(viewportFraction: 0.85),
        itemCount: _imageDocs.length,
        itemBuilder: (context, index) {
          final doc = _imageDocs[index];
          final url = doc['fileUrl'] as String?;
          final summary = doc['aiSummary'] as String? ?? 'No summary available.';
          final title = doc['fileName'] as String? ?? 'Unknown Asset';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 20.0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 8,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: url != null
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : Container(color: Colors.grey),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              summary,
                              style: TextStyle(
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
