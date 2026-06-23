import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neural_canvas/models/chat_session.dart';
import 'package:neural_canvas/utils/ui_utils.dart';

class ChatHistoryScreen extends StatelessWidget {
  final Function(String) onSessionSelected;

  const ChatHistoryScreen({super.key, required this.onSessionSelected});

  String _timeAgo(DateTime d) {
    Duration diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return "${(diff.inDays / 365).floor()} years ago";
    if (diff.inDays > 30) return "${(diff.inDays / 30).floor()} months ago";
    if (diff.inDays > 7) return "${(diff.inDays / 7).floor()} weeks ago";
    if (diff.inDays > 0) return "${diff.inDays} days ago";
    if (diff.inHours > 0) return "${diff.inHours} hours ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes} minutes ago";
    return "just now";
  }

  void _showEditTitleDialog(
    BuildContext context,
    DocumentReference docRef,
    String currentTitle,
  ) {
    final TextEditingController controller = TextEditingController(
      text: currentTitle,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Chat Title'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter custom name...'),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newText = controller.text.trim();
                if (newText.isNotEmpty) {
                  docRef.update({'title': newText});
                }
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text("Please log in to view chat history."));
    }

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chats')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Chat History',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading history: ${snapshot.error}'),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No past conversations.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final session = ChatSession.fromMap(doc.id, data);

              return Dismissible(
                key: Key(session.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  final chatData = doc.data() as Map<String, dynamic>;
                  final chatRef = doc.reference;
                  chatRef.delete();

                  ScaffoldMessenger.of(context).clearSnackBars();
                  UIUtils.showFloatingSnackBar(
                    context,
                    'Chat deleted',
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () {
                        chatRef.set(chatData);
                      },
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      splashColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      highlightColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.05),
                      onTap: () => onSessionSelected(session.id),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.title?.isNotEmpty == true
                                        ? session.title!
                                        : (session.lastMessage.isEmpty
                                              ? "New Conversation"
                                              : session.lastMessage),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.3,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Updated ${_timeAgo(session.updatedAt)}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              onPressed: () {
                                _showEditTitleDialog(
                                  context,
                                  doc.reference,
                                  session.title ?? "",
                                );
                              },
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
    );
  }
}
