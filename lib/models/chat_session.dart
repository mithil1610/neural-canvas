import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSession {
  final String id;
  final String lastMessage;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.lastMessage,
    required this.updatedAt,
  });

  factory ChatSession.fromMap(String id, Map<String, dynamic> data) {
    return ChatSession(
      id: id,
      lastMessage: data['lastMessage'] ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lastMessage': lastMessage,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
