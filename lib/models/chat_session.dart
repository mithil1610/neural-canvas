import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSession {
  final String id;
  final String? title;
  final String lastMessage;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    this.title,
    required this.lastMessage,
    required this.updatedAt,
  });

  factory ChatSession.fromMap(String id, Map<String, dynamic> data) {
    return ChatSession(
      id: id,
      title: data['title'],
      lastMessage: data['lastMessage'] ?? '',
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (title != null) 'title': title,
      'lastMessage': lastMessage,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
