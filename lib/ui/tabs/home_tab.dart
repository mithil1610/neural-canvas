import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:neural_canvas/ui/screens/profile_screen.dart';

// --- Data Models ---

class MemoryReel {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final String timeAgo;
  final int itemCount;
  final String category;

  const MemoryReel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.timeAgo,
    required this.itemCount,
    required this.category,
  });
}

class QuickAction {
  final IconData icon;
  final String label;
  final Color color;

  const QuickAction({required this.icon, required this.label, required this.color});
}

// --- Sample Data ---

const List<MemoryReel> _sampleReels = [
  MemoryReel(
    title: 'Weekend in Austin',
    subtitle: 'Photos, videos & a receipt from the taco place',
    icon: Icons.photo_library_outlined,
    gradientColors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    timeAgo: '2 days ago',
    itemCount: 23,
    category: 'Travel',
  ),
  MemoryReel(
    title: 'Lease Agreement — Apt 4B',
    subtitle: 'OCR extracted. Key dates flagged.',
    icon: Icons.description_outlined,
    gradientColors: [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
    timeAgo: '5 days ago',
    itemCount: 1,
    category: 'Documents',
  ),
  MemoryReel(
    title: 'Design Sprint — Week 12',
    subtitle: 'Whiteboard snapshots & meeting transcript',
    icon: Icons.draw_outlined,
    gradientColors: [Color(0xFFF59E0B), Color(0xFFF97316)],
    timeAgo: '1 week ago',
    itemCount: 14,
    category: 'Work',
  ),
  MemoryReel(
    title: 'Morning Run Highlights',
    subtitle: 'Route map, photos at sunrise, Spotify playlist',
    icon: Icons.directions_run,
    gradientColors: [Color(0xFF10B981), Color(0xFF34D399)],
    timeAgo: '3 days ago',
    itemCount: 8,
    category: 'Health',
  ),
  MemoryReel(
    title: 'Recipe Collection — June',
    subtitle: 'Screenshots from TikTok & handwritten notes',
    icon: Icons.restaurant_menu,
    gradientColors: [Color(0xFFEC4899), Color(0xFFF472B6)],
    timeAgo: 'Yesterday',
    itemCount: 6,
    category: 'Personal',
  ),
];

const List<QuickAction> _quickActions = [
  QuickAction(icon: Icons.camera_alt_outlined, label: 'Scan', color: Color(0xFF818CF8)),
  QuickAction(icon: Icons.mic_none, label: 'Voice Note', color: Color(0xFFA78BFA)),
  QuickAction(icon: Icons.upload_file_outlined, label: 'Import', color: Color(0xFF0EA5E9)),
  QuickAction(icon: Icons.auto_awesome, label: 'Generate', color: Color(0xFFF59E0B)),
];

// --- Widget ---

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            // --- App Bar ---
            SliverAppBar(
              floating: true,
              backgroundColor: cs.surface.withValues(alpha: 0.9),
              elevation: 0,
              title: const Text(
                'Neural Canvas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.5),
              ),
              actions: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ProfileScreen()),
                    ).then((_) {
                      // Trigger a rebuild in case the profile picture was changed
                      if (mounted) setState(() {});
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: StreamBuilder<User?>(
                      stream: FirebaseAuth.instance.userChanges(),
                      builder: (context, snapshot) {
                        final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
                        return CircleAvatar(
                          radius: 16,
                          backgroundColor: cs.surfaceContainerHighest,
                          backgroundImage: user?.photoURL != null
                              ? CachedNetworkImageProvider(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
                              ? Icon(Icons.person, size: 20, color: cs.onSurfaceVariant)
                              : null,
                        );
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: Stack(
                    children: [
                      const Icon(Icons.notifications_none_rounded),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
              ],
            ),

            // --- Greeting ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getGreeting(),
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your memory stream is active.',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),

            // --- Quick Actions ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _quickActions.map((action) {
                    return _buildQuickAction(context, action);
                  }).toList(),
                ),
              ),
            ),

            // --- Section Header ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Memory Reels',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text('See All', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),

            // --- Memory Reel Cards ---
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final reel = _sampleReels[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: _MemoryReelCard(reel: reel),
                  );
                },
                childCount: _sampleReels.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, QuickAction action) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: action.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: action.color.withValues(alpha: 0.3)),
          ),
          child: Icon(action.icon, color: action.color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          action.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning ☀️';
    if (hour < 17) return 'Good afternoon 🌤️';
    return 'Good evening 🌙';
  }
}

// --- Memory Reel Card ---

class _MemoryReelCard extends StatelessWidget {
  final MemoryReel reel;
  const _MemoryReelCard({required this.reel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Gradient icon container
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: reel.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: reel.gradientColors.first.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(reel.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        reel.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reel.subtitle,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildTag(context, reel.category, reel.gradientColors.first),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(
                            reel.timeAgo,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                          ),
                          const Spacer(),
                          Text(
                            '${reel.itemCount} items',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
