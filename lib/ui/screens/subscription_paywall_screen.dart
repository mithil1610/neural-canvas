import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../utils/ui_utils.dart';

class SubscriptionPaywallScreen extends StatefulWidget {
  const SubscriptionPaywallScreen({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SubscriptionPaywallScreen(),
    );
  }

  @override
  State<SubscriptionPaywallScreen> createState() =>
      _SubscriptionPaywallScreenState();
}

class _SubscriptionPaywallScreenState extends State<SubscriptionPaywallScreen> {
  bool _isPurchasing = false;

  Future<void> _simulatePurchase(String targetTier) async {
    HapticFeedback.lightImpact();
    setState(() {
      _isPurchasing = true;
    });

    // Sandbox 1.5s delay
    await Future.delayed(const Duration(milliseconds: 1500));

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'accountTier': targetTier},
      );
    }

    if (!mounted) return;

    setState(() {
      _isPurchasing = false;
    });

    UIUtils.showFloatingSnackBar(
      context,
      "Premium Matrix Link Activated Successfully!",
    );
    Navigator.of(context).pop();
  }

  Widget _buildTierCard({
    required BuildContext context,
    required String title,
    required String price,
    required String description,
    required IconData icon,
    bool isPopular = false,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _isPurchasing ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isPopular
              ? cs.primaryContainer.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPopular
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.2),
            width: isPopular ? 2 : 1,
          ),
          boxShadow: isPopular
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isPopular
                          ? cs.primary.withValues(alpha: 0.2)
                          : cs.onSurfaceVariant.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: isPopular ? cs.primary : cs.onSurfaceVariant,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isPopular ? cs.primary : cs.onSurface,
                              ),
                            ),
                            Text(
                              price,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isPopular)
              Positioned(
                top: 0,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'MOST POPULAR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0F).withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.02),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Ambient purple-indigo glow
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigoAccent.withValues(alpha: 0.1),
                      blurRadius: 100,
                      spreadRadius: 100,
                    ),
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 16, bottom: 24),
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        // Header
                        const Center(
                          child: Icon(
                            Icons.workspace_premium,
                            size: 56,
                            color: Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Unlock Unlimited\nIntelligence',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Elevate your Second Brain to peak performance. Choose the engine that fits your reality.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.6),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Tiers
                        _buildTierCard(
                          context: context,
                          title: 'Base Engine',
                          price: 'Free',
                          description:
                              'Standard indexing and baseline retrieval features.',
                          icon: Icons.memory,
                        ),
                        _buildTierCard(
                          context: context,
                          title: 'Creation Engine',
                          price: '\$19.99/mo',
                          description:
                              'Unlocks advanced AI editing, unlimited narrative generation, and auto-reels.',
                          icon: Icons.auto_awesome,
                          isPopular: true,
                          onTap: () => _simulatePurchase('pro'),
                        ),
                        _buildTierCard(
                          context: context,
                          title: 'Infinite Brain',
                          price: '\$49.99/mo',
                          description:
                              'Unlocks long-term deep personalization models, full cross-format graph mapping, and max storage.',
                          icon: Icons.all_inclusive,
                          onTap: () => _simulatePurchase('premium'),
                        ),
                        _buildTierCard(
                          context: context,
                          title: 'Enterprise Nexus',
                          price: 'Contact Us',
                          description:
                              'Unlocks secure cross-employee shared institutional memory vaults and team knowledge-graph routing. Coming soon.',
                          icon: Icons.business,
                        ),

                        const SizedBox(height: 32),

                        // Action Button
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF334155), Color(0xFF1E3A8A)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _isPurchasing
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(context);
                                    },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    'Activate Matrix Link',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Legal Copy
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Terms of Service',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.4),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '•',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.4),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isPurchasing)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.9,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.02),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: cs.primary),
                            const SizedBox(height: 24),
                            Text(
                              "Contacting App Store\nsecure sandbox gateway...",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
