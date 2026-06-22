import codecs
filepath = 'lib/ui/tabs/home_tab.dart'
with codecs.open(filepath, 'r', 'utf-8') as f:
    content = f.read()

content = content.replace('  final _audioRecorder = AudioRecorder();', '  final _audioRecorder = AudioRecorder();\n  bool hasUnreadNotifications = true;')

content = content.replace('                        Positioned(\n                          right: 0,\n                          top: 0,\n                          child: Container(\n                            width: 8,\n                            height: 8,\n                            decoration: const BoxDecoration(\n                              color: Color(0xFFEF4444),\n                              shape: BoxShape.circle,\n                            ),\n                          ),\n                        ),', '                        if (hasUnreadNotifications)\n                          Positioned(\n                            right: 0,\n                            top: 0,\n                            child: Container(\n                              width: 8,\n                              height: 8,\n                              decoration: const BoxDecoration(\n                                color: Color(0xFFEF4444),\n                                shape: BoxShape.circle,\n                              ),\n                            ),\n                          ),')

on_pressed_old = '''                    onPressed: () {
                      HapticFeedback.lightImpact();
                    },'''

on_pressed_new = '''                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => hasUnreadNotifications = false);
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          return Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            padding: const EdgeInsets.all(24),
                            child: SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "System Update Broadcasts",
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.campaign, color: Colors.blueAccent),
                                    title: const Text("Welcome to Neural Canvas Public Beta v1.0.0. Your initial connection matrix has successfully mapped 200 free operational slots."),
                                  ),
                                  const SizedBox(height: 16),
                                  Center(
                                    child: FilledButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Acknowledge"),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },'''

content = content.replace(on_pressed_old, on_pressed_new)

with codecs.open(filepath, 'w', 'utf-8') as f:
    f.write(content)

print('Done')
