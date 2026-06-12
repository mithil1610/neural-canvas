import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:neural_canvas/models/chat_session.dart';

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
        title: const Text('Chat History', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
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
                  doc.reference.delete();
                },
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.forum_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      session.lastMessage.isEmpty ? "New Conversation" : session.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        _timeAgo(session.updatedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    onTap: () => onSessionSelected(session.id),
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
