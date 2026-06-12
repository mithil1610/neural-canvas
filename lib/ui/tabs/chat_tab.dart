import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neural_canvas/services/ai_service.dart';
import 'package:neural_canvas/models/chat_message.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _aiService.chatHistory.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    _aiService.chatHistory.removeListener(_onHistoryChanged);
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    // Scroll to bottom whenever history changes
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSubmitted(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    // Check if AI is currently typing
    final history = _aiService.chatHistory.value;
    if (history.isNotEmpty && history.last.isStreaming) return;

    _textController.clear();
    await _aiService.sendUserMessage(trimmedText);
    
    _focusNode.requestFocus();
  }

  Future<void> _handleAttachment() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to upload media.')),
        );
        return;
      }

      // Show uploading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading attachment...')),
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = file.name;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/${user.uid}/uploads/${timestamp}_$fileName');

      UploadTask uploadTask;
      if (kIsWeb) {
        uploadTask = storageRef.putData(file.bytes!);
      } else {
        uploadTask = storageRef.putFile(File(file.path!));
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Append directly to Firestore as requested
      if (_aiService.currentSessionId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('chats')
            .doc(_aiService.currentSessionId)
            .collection('messages')
            .add({
          'text': 'Attachment: $downloadUrl',
          'isAssistant': false,
          'isSystem': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      
      // Also add to local UI state so the user sees it
      _aiService.sendUserMessage('Attachment: $downloadUrl');
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Assistant', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Chat',
            onPressed: () => _aiService.clearHistory(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: _aiService.chatHistory,
              builder: (context, messages, child) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: _buildMessageBubble(context, msg),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _handleAttachment,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      child: ValueListenableBuilder<List<ChatMessage>>(
                        valueListenable: _aiService.chatHistory,
                        builder: (context, messages, _) {
                          final isTyping = messages.isNotEmpty && messages.last.isStreaming;
                          return TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            onSubmitted: _handleSubmitted,
                            enabled: !isTyping,
                            decoration: InputDecoration(
                              hintText: isTyping ? 'Assistant is typing...' : 'Ask your assistant...',
                              hintStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<List<ChatMessage>>(
                    valueListenable: _aiService.chatHistory,
                    builder: (context, messages, _) {
                      final isTyping = messages.isNotEmpty && messages.last.isStreaming;
                      return IconButton(
                        icon: isTyping 
                            ? const SizedBox(
                                width: 24, 
                                height: 24, 
                                child: CircularProgressIndicator(strokeWidth: 2)
                              ) 
                            : const Icon(Icons.send),
                        onPressed: isTyping ? null : () => _handleSubmitted(_textController.text),
                        color: Theme.of(context).colorScheme.primary,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    if (message.isSystem) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final bgColor = message.isAssistant
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.primary;
    final textColor = message.isAssistant
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onPrimary;
    final alignment = message.isAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: message.isAssistant ? const Radius.circular(4) : const Radius.circular(20),
      bottomRight: message.isAssistant ? const Radius.circular(20) : const Radius.circular(4),
    );

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: message.text.isEmpty && message.isStreaming
                    ? Text(
                        "Thinking...",
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.5),
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : MarkdownBody(
                        data: message.text,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: textColor, fontSize: 16),
                          code: TextStyle(
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            color: Theme.of(context).colorScheme.onSurface,
                            fontFamily: 'monospace',
                          ),
                          codeblockPadding: const EdgeInsets.all(8),
                          codeblockDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
              ),
              if (message.isStreaming && message.text.isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 16,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
