import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ReelStoryboardScreen extends StatefulWidget {
  final String dateKey;
  final List<QueryDocumentSnapshot> clusterItems;

  const ReelStoryboardScreen({
    super.key,
    required this.dateKey,
    required this.clusterItems,
  });

  @override
  State<ReelStoryboardScreen> createState() => _ReelStoryboardScreenState();
}

class _ReelStoryboardScreenState extends State<ReelStoryboardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  
  bool _isLoading = true;
  String _storyboardMarkdown = "";

  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    
    _generateStoryboard();
  }

  Future<void> _generateStoryboard() async {
    if (_geminiApiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _storyboardMarkdown = "> **Error:** GEMINI_API_KEY not configured.";
        });
        _animController.forward();
      }
      return;
    }

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _geminiApiKey);
      
      List<String> summaries = widget.clusterItems.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['aiSummary']?.toString() ?? '';
      }).where((s) => s.isNotEmpty).toList();

      final prompt = """
Act as a Master Short-Form Director. Analyze these media segment summaries representing a cluster of memories. 
Synthesize a definitive chronological video narrative story arc script layout. 
Generate dynamic subtitle text overlays for every slide/scene transition and suggest an overarching theme vibe or musical tempo score template. 
Package everything into a striking markdown screen array using ## headers, bullet points, and blockquotes for visual flair.

Summaries:
${summaries.join('\n\n---\n\n')}
""";

      final response = await model.generateContent([Content.text(prompt)]);
      
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _storyboardMarkdown = response.text ?? "> **Notice:** The director could not assemble a narrative from these segments.";
      });
      _animController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _storyboardMarkdown = "> **Error assembling storyboard:** \$e";
      });
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Ambient blurred background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Colors.black],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Reel Storyboard // ${widget.dateKey}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                              SizedBox(height: 24),
                              Text("Synthesizing Narrative...", style: TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 1.2)),
                            ],
                          ),
                        )
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            child: MarkdownBody(
                              data: _storyboardMarkdown,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                                h1: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.4),
                                h2: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600, height: 1.4),
                                h3: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                blockquote: const TextStyle(color: Color(0xFFA78BFA), fontSize: 16, fontStyle: FontStyle.italic),
                                blockquoteDecoration: BoxDecoration(
                                  border: const Border(left: BorderSide(color: Color(0xFFA78BFA), width: 4)),
                                  color: const Color(0xFFA78BFA).withValues(alpha: 0.1),
                                ),
                                listBullet: const TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
