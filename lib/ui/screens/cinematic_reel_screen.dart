import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';


class CinematicReelScreen extends StatefulWidget {
  const CinematicReelScreen({Key? key}) : super(key: key);

  @override
  State<CinematicReelScreen> createState() => _CinematicReelScreenState();
}

class _CinematicReelScreenState extends State<CinematicReelScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  List<DocumentSnapshot> _mediaDocs = [];
  bool _isLoading = true;
  Timer? _autoPlayTimer;
  bool _isDownloading = false;
  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchRecentMedia();
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  void _speakCurrentSummary() {
    if (_mediaDocs.isEmpty) return;
    final doc = _mediaDocs[_currentIndex];
    final summary = doc['aiSummary'] as String? ?? '';
    if (summary.isNotEmpty) {
      final cleanText = summary.replaceAll(RegExp(r'[*_#]'), '');
      flutterTts.speak(cleanText);
    }
  }

  Future<void> _downloadMedia(String url) async {
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(url));
      final dir = await getTemporaryDirectory();
      final ext = url.split('?').first.split('.').last;
      final extToUse = (ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'mp4') ? ext : 'jpg';
      final file = File('${dir.path}/reel_export_${DateTime.now().millisecondsSinceEpoch}.$extToUse');
      await file.writeAsBytes(response.bodyBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Exported from Axiom');
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      setState(() => _isDownloading = false);
    }
  }


  Future<void> _fetchRecentMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('knowledge_base')
          .orderBy('uploadedAt', descending: true)
          .limit(5)
          .get();

      setState(() {
        _mediaDocs = snapshot.docs.where((doc) {
          final type = doc['fileType'] as String? ?? '';
          return type == 'png' || type == 'jpg' || type == 'jpeg';
        }).toList();
        _isLoading = false;
      });

      if (_mediaDocs.isNotEmpty) {
        _startAutoPlay();
        _speakCurrentSummary();
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentIndex < _mediaDocs.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoPlayTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_mediaDocs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text(
            "No recent visual media found to generate a reel.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _speakCurrentSummary();
            },
            itemCount: _mediaDocs.length,
            itemBuilder: (context, index) {
              final doc = _mediaDocs[index];
              final url = doc['fileUrl'] as String?;
              final summary = doc['aiSummary'] as String? ?? '';
              
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    AnimatedOpacity(
                      opacity: _currentIndex == index ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 800),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 60,
                    left: 20,
                    right: 20,
                    child: _TypewriterText(
                      text: summary,
                      key: ValueKey(index),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                if (_isDownloading)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white, size: 30),
                    onPressed: () {
                      final doc = _mediaDocs[_currentIndex];
                      final url = doc['fileUrl'] as String?;
                      if (url != null) _downloadMedia(url);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypewriterText extends StatefulWidget {
  final String text;
  const _TypewriterText({Key? key, required this.text}) : super(key: key);

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayedText = "";
  Timer? _timer;
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (_charIndex < widget.text.length) {
        setState(() {
          _displayedText += widget.text[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        height: 1.4,
        shadows: [
          Shadow(
            color: Colors.black,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
