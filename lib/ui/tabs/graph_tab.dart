import 'package:flutter/material.dart';


// --- Data Models ---

class GraphNode {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final double size;
  final List<String> connections;
  final String description;
  Offset position;

  GraphNode({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.size,
    required this.connections,
    required this.description,
    required this.position,
  });
}

// --- Widget ---

class GraphTab extends StatefulWidget {
  const GraphTab({super.key});

  @override
  State<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<GraphTab> with TickerProviderStateMixin {
  late final List<GraphNode> _nodes;
  String? _selectedNodeId;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // For pan/zoom
  Offset _panOffset = Offset.zero;


  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initializeNodes();
  }

  void _initializeNodes() {
    // These positions are relative offsets from center; they'll be adjusted in build
    _nodes = [
      GraphNode(
        id: 'core',
        label: 'You',
        icon: Icons.psychology,
        color: const Color(0xFF818CF8),
        size: 72,
        connections: ['docs', 'photos', 'events', 'people', 'health', 'work'],
        description: 'Your central identity node — all memories connect here.',
        position: Offset.zero,
      ),
      GraphNode(
        id: 'docs',
        label: 'Documents',
        icon: Icons.description_outlined,
        color: const Color(0xFF0EA5E9),
        size: 52,
        connections: ['core', 'work'],
        description: '3 docs • Lease, insurance card, meeting notes',
        position: const Offset(-140, -160),
      ),
      GraphNode(
        id: 'photos',
        label: 'Photos',
        icon: Icons.photo_library_outlined,
        color: const Color(0xFF6366F1),
        size: 52,
        connections: ['core', 'events'],
        description: '23 photos • Austin trip, sunrise run, whiteboard',
        position: const Offset(150, -130),
      ),
      GraphNode(
        id: 'events',
        label: 'Events',
        icon: Icons.calendar_today,
        color: const Color(0xFFF59E0B),
        size: 48,
        connections: ['core', 'photos', 'people'],
        description: '5 events • ACL Fest, VC call, design sprint',
        position: const Offset(-160, 100),
      ),
      GraphNode(
        id: 'people',
        label: 'People',
        icon: Icons.people_outline,
        color: const Color(0xFFEC4899),
        size: 48,
        connections: ['core', 'events'],
        description: '8 contacts • J. Patel, design team, investors',
        position: const Offset(160, 110),
      ),
      GraphNode(
        id: 'health',
        label: 'Health',
        icon: Icons.favorite_outline,
        color: const Color(0xFF10B981),
        size: 44,
        connections: ['core'],
        description: '4 entries • Morning runs, insurance, fitness goals',
        position: const Offset(-60, 200),
      ),
      GraphNode(
        id: 'work',
        label: 'Work',
        icon: Icons.work_outline,
        color: const Color(0xFFA78BFA),
        size: 48,
        connections: ['core', 'docs'],
        description: '6 items • Design sprints, meeting notes, wireframes',
        position: const Offset(70, -220),
      ),
    ];
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  GraphNode? get _selectedNode {
    if (_selectedNodeId == null) return null;
    return _nodes.firstWhere((n) => n.id == _selectedNodeId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // --- Interactive Graph Canvas ---
          GestureDetector(
            onPanUpdate: (details) {
              setState(() => _panOffset += details.delta);
            },
            onDoubleTap: () {
              setState(() {
                _panOffset = Offset.zero;
                _selectedNodeId = null;
              });
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _GraphEdgePainter(
                    nodes: _nodes,
                    panOffset: _panOffset,
                    screenCenter: Offset(
                      MediaQuery.of(context).size.width / 2,
                      MediaQuery.of(context).size.height / 2 - 40,
                    ),
                    pulseValue: _pulseAnimation.value,
                    selectedNodeId: _selectedNodeId,
                  ),
                  child: child,
                );
              },
            ),
          ),

          // --- Graph Nodes ---
          ..._nodes.map((node) => _buildDraggableNode(context, node)),

          // --- Title ---
          Positioned(
            top: 56,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Knowledge Graph',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_nodes.length} nodes • ${_countEdges()} connections',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: const Color(0xFF10B981), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- Selected Node Info Card ---
          if (_selectedNode != null)
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: _buildInfoCard(context, _selectedNode!),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggableNode(BuildContext context, GraphNode node) {
    final center = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height / 2 - 40,
    );
    final pos = center + node.position + _panOffset;
    final isSelected = _selectedNodeId == node.id;
    final isCentral = node.id == 'core';

    return Positioned(
      left: pos.dx - node.size / 2,
      top: pos.dy - node.size / 2,
      child: GestureDetector(
        onTap: () => setState(() => _selectedNodeId = isSelected ? null : node.id),
        onPanUpdate: (details) {
          setState(() => node.position += details.delta);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: node.size,
          height: node.size,
          decoration: BoxDecoration(
            color: isSelected || isCentral ? node.color : node.color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : node.color.withValues(alpha: 0.6),
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: node.color.withValues(alpha: isSelected ? 0.5 : isCentral ? 0.3 : 0.15),
                blurRadius: isSelected ? 24 : isCentral ? 16 : 8,
                spreadRadius: isSelected ? 4 : isCentral ? 2 : 0,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                node.icon,
                color: isSelected || isCentral ? Colors.white : node.color,
                size: node.size * 0.38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, GraphNode node) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: node.color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(node.icon, color: node.color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(node.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  node.description,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '${node.connections.length} connections',
                  style: TextStyle(fontSize: 11, color: node.color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
            onPressed: () => setState(() => _selectedNodeId = null),
          ),
        ],
      ),
    );
  }

  int _countEdges() {
    final Set<String> edges = {};
    for (var node in _nodes) {
      for (var conn in node.connections) {
        final key = [node.id, conn]..sort();
        edges.add(key.join('-'));
      }
    }
    return edges.length;
  }
}

// --- Edge Painter ---

class _GraphEdgePainter extends CustomPainter {
  final List<GraphNode> nodes;
  final Offset panOffset;
  final Offset screenCenter;
  final double pulseValue;
  final String? selectedNodeId;

  _GraphEdgePainter({
    required this.nodes,
    required this.panOffset,
    required this.screenCenter,
    required this.pulseValue,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Offset> positions = {};
    for (var node in nodes) {
      positions[node.id] = screenCenter + node.position + panOffset;
    }

    // Draw edges
    final Set<String> drawn = {};
    for (var node in nodes) {
      for (var connId in node.connections) {
        final key = [node.id, connId]..sort();
        final edgeKey = key.join('-');
        if (drawn.contains(edgeKey)) continue;
        drawn.add(edgeKey);

        final from = positions[node.id];
        final to = positions[connId];
        if (from == null || to == null) continue;

        final isHighlighted = selectedNodeId != null &&
            (node.id == selectedNodeId || connId == selectedNodeId);

        final paint = Paint()
          ..color = isHighlighted
              ? node.color.withValues(alpha: 0.5 + pulseValue * 0.3)
              : node.color.withValues(alpha: 0.12 + pulseValue * 0.06)
          ..strokeWidth = isHighlighted ? 2.5 : 1.5
          ..style = PaintingStyle.stroke;

        canvas.drawLine(from, to, paint);

        // Draw a subtle glow dot at the midpoint
        if (isHighlighted) {
          final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
          final dotPaint = Paint()
            ..color = node.color.withValues(alpha: 0.4 + pulseValue * 0.4)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(mid, 3, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) => true;
}
