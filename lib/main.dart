import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:neural_canvas/screens/auth_gate.dart';
import 'package:neural_canvas/ui/tabs/chat_tab.dart';
import 'package:neural_canvas/ui/tabs/graph_tab.dart';
import 'package:neural_canvas/ui/tabs/home_tab.dart';
import 'package:neural_canvas/ui/tabs/search_tab.dart';
import 'package:neural_canvas/screens/chat_history_screen.dart';
import 'package:neural_canvas/services/share_receiver_service.dart';
import 'package:neural_canvas/services/ai_service.dart';
import 'package:neural_canvas/widgets/ai_processing_overlay.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<int> globalTabController = ValueNotifier<int>(0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }

  runApp(const NeuralCanvasApp());
}

class NeuralCanvasApp extends StatelessWidget {
  const NeuralCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Neural Canvas',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(children: [child!, const AiProcessingOverlay()]);
      },
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF818CF8), // Indigo 400
          onPrimary: Colors.white,
          secondary: Color(0xFFA78BFA), // Violet 400
          onSecondary: Colors.white,
          surface: Color(0xFF0F172A), // Slate 900
          onSurface: Color(0xFFF8FAFC), // Slate 50
          surfaceContainerHighest: Color(0xFF1E293B), // Slate 800
          surfaceContainerHigh: Color(0xFF334155), // Slate 700
          surfaceContainerLow: Color(0xFF0B1120), // Slate 950
          outlineVariant: Color(0xFF475569), // Slate 600
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        fontFamily:
            'Inter', // Assuming standard system font if Inter isn't loaded
      ),
      home: const AuthGate(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Begin listening for shared files the absolute second the app boots up
    ShareReceiverService().initialize(navigatorKey);
    globalTabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (globalTabController.value != _currentIndex && mounted) {
      setState(() {
        _currentIndex = globalTabController.value;
      });
    }
  }

  @override
  void dispose() {
    globalTabController.removeListener(_onTabChanged);
    ShareReceiverService().dispose();
    super.dispose();
  }

  List<Widget> get _tabs => [
    const HomeTab(),
    const SearchTab(),
    const GraphTab(),
    ChatHistoryScreen(
      onSessionSelected: (sessionId) {
        AiService().loadSession(sessionId);
        setState(() {
          _currentIndex = 4;
        });
      },
    ),
    const ChatTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _tabs[_currentIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.2),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                );
              }
              return TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              );
            }),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              globalTabController.value = index;
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view),
                selectedIcon: Icon(Icons.grid_view, color: Color(0xFF818CF8)),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search, color: Color(0xFF818CF8)),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(
                  Icons.account_tree,
                  color: Color(0xFF818CF8),
                ),
                label: 'Graph',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history, color: Color(0xFF818CF8)),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble, color: Color(0xFF818CF8)),
                label: 'Chat',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
