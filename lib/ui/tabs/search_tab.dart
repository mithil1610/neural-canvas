import 'package:flutter/material.dart';

// --- Data Model ---

class MemoryItem {
  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final Color color;
  final String date;
  final List<String> tags;

  const MemoryItem({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.color,
    required this.date,
    required this.tags,
  });
}

// --- Sample Data ---

const List<MemoryItem> _allItems = [
  MemoryItem(
    title: 'Lease Agreement — Apt 4B',
    subtitle: 'Move-in: Aug 1. Landlord: J. Patel. Rent: \$2,150/mo.',
    category: 'Documents',
    icon: Icons.description_outlined,
    color: Color(0xFF0EA5E9),
    date: 'Jun 3, 2026',
    tags: ['pdf', 'lease', 'apartment', 'contract', 'legal'],
  ),
  MemoryItem(
    title: 'Austin Trip — Day 1 Photos',
    subtitle: '23 photos from 6th Street, Congress Bridge bats at sunset.',
    category: 'Photos',
    icon: Icons.photo_library_outlined,
    color: Color(0xFF6366F1),
    date: 'Jun 1, 2026',
    tags: ['travel', 'austin', 'photos', 'sunset', 'trip'],
  ),
  MemoryItem(
    title: 'Design Sprint Whiteboard',
    subtitle: 'Week 12 brainstorm. Wireframes for Neural Canvas onboarding.',
    category: 'Work',
    icon: Icons.draw_outlined,
    color: Color(0xFFF59E0B),
    date: 'May 30, 2026',
    tags: ['work', 'design', 'whiteboard', 'sprint', 'wireframe'],
  ),
  MemoryItem(
    title: 'Morning Run — Town Lake',
    subtitle: '5.2 mi, 42:18. Route map + sunrise photo at Lamar Blvd.',
    category: 'Health',
    icon: Icons.directions_run,
    color: Color(0xFF10B981),
    date: 'Jun 2, 2026',
    tags: ['run', 'fitness', 'health', 'route', 'morning'],
  ),
  MemoryItem(
    title: 'Pasta Recipe — TikTok Save',
    subtitle: 'Lemon ricotta pasta. Screenshot + handwritten notes.',
    category: 'Personal',
    icon: Icons.restaurant_menu,
    color: Color(0xFFEC4899),
    date: 'May 29, 2026',
    tags: ['recipe', 'food', 'cooking', 'tiktok', 'personal'],
  ),
  MemoryItem(
    title: 'Meeting Notes — VC Call',
    subtitle: 'Investor Q&A. Cap table review. Follow-up action items.',
    category: 'Work',
    icon: Icons.note_alt_outlined,
    color: Color(0xFFA78BFA),
    date: 'May 28, 2026',
    tags: ['meeting', 'notes', 'investor', 'startup', 'work'],
  ),
  MemoryItem(
    title: 'Insurance Card — Scan',
    subtitle: 'Blue Cross Blue Shield. Policy #HX-449201. Exp: Dec 2026.',
    category: 'Documents',
    icon: Icons.badge_outlined,
    color: Color(0xFF0EA5E9),
    date: 'May 25, 2026',
    tags: ['insurance', 'health', 'card', 'scan', 'document'],
  ),
  MemoryItem(
    title: 'Concert Video — ACL Fest',
    subtitle: '45s clip of headliner set. Crowd energy was incredible.',
    category: 'Videos',
    icon: Icons.videocam_outlined,
    color: Color(0xFFF97316),
    date: 'May 20, 2026',
    tags: ['video', 'concert', 'music', 'acl', 'festival'],
  ),
];

const List<String> _filterCategories = ['All', 'Documents', 'Photos', 'Videos', 'Work', 'Health', 'Personal'];

// --- Widget ---

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  List<MemoryItem> get _filteredItems {
    return _allItems.where((item) {
      final matchesCategory = _selectedCategory == 'All' || item.category == _selectedCategory;
      if (_query.isEmpty) return matchesCategory;

      final q = _query.toLowerCase();
      final matchesQuery = item.title.toLowerCase().contains(q) ||
          item.subtitle.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q) ||
          item.tags.any((tag) => tag.contains(q));

      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = _filteredItems;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Text(
                'Explore',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Search Bar ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(color: cs.primary.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: 2),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search memories, documents, photos...',
                    hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 15),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.search, size: 22, color: cs.primary),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.mic_none, size: 22, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Category Chips ---
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _filterCategories.length,
                separatorBuilder: (context2, index2) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _filterCategories[index];
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? cs.primary : cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // --- Results Count ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '${results.length} ${results.length == 1 ? 'result' : 'results'}${_query.isNotEmpty ? ' for "$_query"' : ''}',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(height: 12),

            // --- Results List ---
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No memories found',
                            style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try a different search or category',
                            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        return _SearchResultTile(item: results[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Search Result Tile ---

class _SearchResultTile extends StatelessWidget {
  final MemoryItem item;
  const _SearchResultTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(item.date, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.category,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: item.color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
