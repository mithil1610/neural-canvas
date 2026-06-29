import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchRecentMedia();
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
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
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
