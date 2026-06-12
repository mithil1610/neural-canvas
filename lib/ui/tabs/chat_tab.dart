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
import 'package:cached_network_image/cached_network_image.dart';

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
  PlatformFile? _selectedAttachment;

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
    if (trimmedText.isEmpty && _selectedAttachment == null) return;

    final history = _aiService.chatHistory.value;
    if (history.isNotEmpty && history.last.isStreaming) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in first.')),
        );
      }
      return;
    }

    String? mediaUrl;
    String messageType = 'text';
    final attachment = _selectedAttachment;
    
    // Capture state variables locally and reset UI
    _textController.clear();
    setState(() {
      _selectedAttachment = null;
    });

    if (attachment != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading attachment...')),
        );
      }
      
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = attachment.name;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users/${user.uid}/uploads/${timestamp}_$fileName');

        UploadTask uploadTask;
        if (kIsWeb) {
          uploadTask = storageRef.putData(attachment.bytes!);
        } else {
          uploadTask = storageRef.putFile(File(attachment.path!));
        }

        final snapshot = await uploadTask;
        mediaUrl = await snapshot.ref.getDownloadURL();
        
        if (trimmedText.isNotEmpty) {
          messageType = 'mixed';
        } else {
          final ext = attachment.extension?.toLowerCase();
          messageType = (ext == 'pdf' || ext == 'doc' || ext == 'txt') ? 'file' : 'image';
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e')),
          );
        }
        return;
      }
    }

    // 1. Execute direct Firestore write mapping
    final payload = <String, dynamic>{
      'senderId': user.uid,
      'role': 'user',
      'timestamp': FieldValue.serverTimestamp(),
      'type': messageType,
    };

    if (messageType == 'text') {
      payload['content'] = trimmedText;
    } else if (messageType == 'mixed') {
      payload['content'] = trimmedText;
      payload['mediaUrl'] = mediaUrl;
      payload['fileName'] = attachment?.name;
    } else {
      payload['content'] = mediaUrl;
      payload['fileName'] = attachment?.name;
    }

    // Ensure we have an active chat session ID
    String activeChatId = _aiService.currentSessionId ?? 
        FirebaseFirestore.instance.collection('users').doc(user.uid).collection('chats').doc().id;
    
    _aiService.currentSessionId = activeChatId;

    // Ensure the root chat document exists
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chats')
        .doc(activeChatId)
        .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    // Push the payload into the messages sub-collection
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chats')
        .doc(activeChatId)
        .collection('messages')
        .add(payload);

    // 2. Fallback to trigger the AI backend so the chat actually progresses
    if (mediaUrl != null) {
      _aiService.sendSystemContext(
        trimmedText.isNotEmpty ? trimmedText : "I have attached a $messageType.", 
        mediaPath: mediaUrl, 
        mediaType: messageType,
      );
    } else {
      _aiService.sendUserMessage(trimmedText);
    }

    _focusNode.requestFocus();
  }

  Future<void> _handleAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      setState(() {
        _selectedAttachment = result.files.first;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
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
              builder: (context, localMessages, child) {
                final user = FirebaseAuth.instance.currentUser;
                final activeChatId = _aiService.currentSessionId;
                
                // 1. If we have no active chat yet, just show the local welcome message
                if (user == null || activeChatId == null) {
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: localMessages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _buildLegacyBubble(context, localMessages[index]),
                      );
                    },
                  );
                }

                // 2. StreamBuilder to read from Firestore directly
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('chats')
                      .doc(activeChatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('Error loading chat'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snapshot.data?.docs ?? [];
                    
                    // The streaming AI message (if any) should be at index 0 (the bottom) since we are using reverse: true
                    final streamingMessage = localMessages.where((m) => m.isStreaming).lastOrNull;
                    
                    final itemCount = docs.length + (streamingMessage != null ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true, // As requested, build from bottom up
                      padding: const EdgeInsets.all(16.0),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        // Render the hybrid local streaming message at the absolute bottom
                        if (streamingMessage != null && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: _buildLegacyBubble(context, streamingMessage),
                          );
                        }
                        
                        // Shift index if streaming message exists
                        final docIndex = streamingMessage != null ? index - 1 : index;
                        final docData = docs[docIndex].data() as Map<String, dynamic>;
                        
                        // We use top padding instead of bottom because the list is reversed
                        return Padding(
                          padding: const EdgeInsets.only(top: 16.0), 
                          child: _buildStreamBubble(context, docData),
                        );
                      },
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedAttachment != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file, color: Theme.of(context).colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedAttachment!.name,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () => setState(() => _selectedAttachment = null),
                            child: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                          ),
                        ],
                      ),
                    ),
                  Row(
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamBubble(BuildContext context, Map<String, dynamic> data) {
    final role = data['role'] ?? 'user';
    final type = data['type'] ?? 'text';
    final content = data['content'] ?? '';
    final mediaUrl = data['mediaUrl'];
    final isAssistant = role == 'ai' || role == 'assistant' || role == 'system';

    final bgColor = isAssistant
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.primary;
    final textColor = isAssistant
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onPrimary;
    final alignment = isAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: isAssistant ? const Radius.circular(4) : const Radius.circular(20),
      bottomRight: isAssistant ? const Radius.circular(20) : const Radius.circular(4),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Render Media (Image or Mixed)
              if (type == 'image' || type == 'mixed') ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: type == 'mixed' ? mediaUrl : content,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const SizedBox(
                      width: 150,
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const SizedBox(
                      width: 150,
                      height: 150,
                      child: Center(child: Icon(Icons.error)),
                    ),
                  ),
                ),
                if (type == 'mixed' && content.toString().isNotEmpty) const SizedBox(height: 8),
              ],
              
              // Render Text Content
              if (type == 'text' || type == 'mixed' || type == 'file')
                MarkdownBody(
                  data: type == 'mixed' ? content : (type == 'file' ? 'Attached file: $content' : content),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegacyBubble(BuildContext context, ChatMessage message) {
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
