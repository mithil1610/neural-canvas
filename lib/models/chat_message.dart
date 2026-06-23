class ChatMessage {
  final String text;
  final bool isAssistant;
  final bool isStreaming;
  final bool isSystem;

  const ChatMessage({
    required this.text,
    required this.isAssistant,
    this.isStreaming = false,
    this.isSystem = false,
  });

  ChatMessage copyWith({
    String? text,
    bool? isAssistant,
    bool? isStreaming,
    bool? isSystem,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isAssistant: isAssistant ?? this.isAssistant,
      isStreaming: isStreaming ?? this.isStreaming,
      isSystem: isSystem ?? this.isSystem,
    );
  }
}
