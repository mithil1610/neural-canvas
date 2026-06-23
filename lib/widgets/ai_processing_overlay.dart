import 'dart:ui';
import 'package:flutter/material.dart';

enum AiProcessingType { pdf, image, video, text, unknown }

class AiProcessingData {
  final AiProcessingType type;
  const AiProcessingData(this.type);

  String get message {
    switch (type) {
      case AiProcessingType.pdf:
        return "Axiom is analyzing your document clauses...";
      case AiProcessingType.image:
        return "Running OCR and extracting memories...";
      case AiProcessingType.video:
        return "Mapping scene structures and mood...";
      case AiProcessingType.text:
      case AiProcessingType.unknown:
        return "Axiom is analyzing your shared asset...";
    }
  }

  IconData get icon {
    switch (type) {
      case AiProcessingType.pdf:
        return Icons.description_outlined;
      case AiProcessingType.image:
        return Icons.image_search_outlined;
      case AiProcessingType.video:
        return Icons.video_camera_front_outlined;
      case AiProcessingType.text:
        return Icons.text_snippet_outlined;
      case AiProcessingType.unknown:
        return Icons.auto_awesome;
    }
  }
}

// Global state variable
final ValueNotifier<AiProcessingData?> globalAiProcessingState = ValueNotifier(
  null,
);

class AiProcessingOverlay extends StatelessWidget {
  const AiProcessingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AiProcessingData?>(
      valueListenable: globalAiProcessingState,
      builder: (context, processingData, child) {
        if (processingData == null) {
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Opacity(opacity: value, child: child);
            },
            child: Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // Glassmorphism background
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),

                  // Content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pulsing Icon / Loading Animation
                        _PulsingIcon(icon: processingData.icon),
                        const SizedBox(height: 32),

                        // Dynamic Text
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40.0),
                          child: Text(
                            processingData.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  const _PulsingIcon({required this.icon});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow pulse
            Container(
              width: 100 * _scaleAnimation.value,
              height: 100 * _scaleAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: 0.2 * _opacityAnimation.value,
                ),
              ),
            ),
            // Inner circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 20 * _scaleAnimation.value,
                    spreadRadius: 5 * _scaleAnimation.value,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
                    ),
                  ),
                  Icon(widget.icon, size: 32, color: Colors.white),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
