import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChronosMatrixScreen extends StatelessWidget {
  const ChronosMatrixScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () { HapticFeedback.lightImpact(); Navigator.of(context).pop(); },
        ),
        title: const Text(
          "CHRONOS MATRIX",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(child: Text("Sign in to view timeline."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('upcoming_events')
                  .where('eventDateTime', isGreaterThanOrEqualTo: DateTime.now().toIso8601String())
                  .orderBy('eventDateTime', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error loading events: \${snapshot.error}"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final events = snapshot.data!.docs;
                if (events.isEmpty) {
                  return Center(
                    child: Text(
                      "No upcoming events detected in your timeline.",
                      style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final data = events[index].data() as Map<String, dynamic>;
                    final title = data['eventTitle'] ?? 'Event';
                    final time = data['eventDateTime'] ?? 'TBD';
                    final location = data['eventLocation'] ?? 'TBD';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on_outlined, color: Color(0xFF10B981)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.schedule, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      time,
                                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
