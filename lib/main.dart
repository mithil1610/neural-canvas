import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'firebase_options.dart';

import 'package:neural_canvas/screens/auth_gate.dart';
import 'package:neural_canvas/ui/screens/knowledge_base_screen.dart';
import 'package:neural_canvas/ui/tabs/graph_tab.dart';
import 'package:neural_canvas/ui/tabs/home_tab.dart';
import 'package:neural_canvas/ui/tabs/chat_tab.dart';
import 'package:neural_canvas/screens/chat_history_screen.dart';

import 'package:neural_canvas/services/ai_service.dart';
import 'package:neural_canvas/widgets/ai_processing_overlay.dart';
import 'package:neural_canvas/services/notification_service.dart';
import 'package:neural_canvas/services/share_receiver_service.dart';
import 'package:neural_canvas/ui/screens/chronos_matrix_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:io' show Platform;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<int> globalTabController = ValueNotifier<int>(0);

class MainRouter {
  static bool bypassBiometricsOnce = false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (Platform.isIOS) {
      await FirebaseAppCheck.instance.activate(
        providerApple: AppleAppAttestProvider(),
      );

      await Purchases.configure(
        PurchasesConfiguration("appl_DIumzQmJmaNDOQiPrfxmrLWixBy"),
      );

      Purchases.addCustomerInfoUpdateListener((customerInfo) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          String newTier = "Free";
          if (customerInfo.entitlements.all["infinite_brain"]?.isActive ==
              true) {
            newTier = "Infinite Brain";
          } else if (customerInfo
                  .entitlements
                  .all["creation_engine"]
                  ?.isActive ==
              true) {
            newTier = "Creation Engine";
          }

          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'accountTier': newTier});
          } catch (e) {
            if (kDebugMode)
              debugPrint("Failed to sync RevenueCat entitlement: $e");
          }
        }
      });
    }

    // Route structural framework errors directly into your reporting channels
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    if (kDebugMode) debugPrint("Firebase init failed: $e");
  }

  tz.initializeTimeZones();
  await NotificationService().initialize();

  runApp(const NeuralCanvasApp());
}

class NeuralCanvasApp extends StatelessWidget {
  const NeuralCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Axiom',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(children: [child!, const AiProcessingOverlay()]);
      },
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF818CF8),
          onPrimary: Colors.white,
          secondary: Color(0xFFA78BFA),
          onSecondary: Colors.white,
          surface: Color(0xFF0A0A0E),
          onSurface: Color(0xFFF8FAFC),
          surfaceContainerHighest: Color(0xFF1E293B),
          surfaceContainerHigh: Color(0xFF334155),
          surfaceContainerLow: Color(0xFF0B1120),
          outlineVariant: Color(0xFF475569),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0E),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      routes: {
        '/chronosMatrix': (context) => const ChronosMatrixScreen(),
        '/login_or_register': (context) => const AuthGate(),
      },
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
  final LocalAuthentication auth = LocalAuthentication();
  bool _isUnlocked = false;

  @override
  void initState() {
    super.initState();
    globalTabController.addListener(_onTabChanged);

    // Completely isolates and instantiates incoming share intents via a single stream listener
    ShareReceiverService().initialize(navigatorKey);

    if (MainRouter.bypassBiometricsOnce) {
      MainRouter.bypassBiometricsOnce = false;
      _navigateToHome();
    } else {
      _authenticateBiometrics();
    }
  }

  void _navigateToHome() {
    if (mounted) {
      setState(() {
        _isUnlocked = true;
      });
    }
  }

  void _navigateToLoginScreen() {
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login_or_register');
    }
  }

  Future<void> _authenticateBiometrics() async {
    try {
      bool canCheck = await auth.canCheckBiometrics;
      bool isSupported = await auth.isDeviceSupported();

      if (!canCheck || !isSupported) {
        _navigateToHome();
        return;
      }

      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please unlock to access your Axiom workspace',
        options: const AuthenticationOptions(
          stickyAuth: false,
          biometricOnly: false,
        ),
      );

      if (didAuthenticate) {
        _navigateToHome();
      } else {
        if (FirebaseAuth.instance.currentUser != null) {
          _navigateToHome();
        } else {
          await FirebaseAuth.instance.signOut();
          _navigateToLoginScreen();
        }
      }
    } catch (e) {
      _navigateToHome();
    }
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
    super.dispose();
  }

  List<Widget> get _tabs => [
    const HomeTab(),
    const KnowledgeBaseScreen(),
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
    if (!_isUnlocked) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Matrix Locked',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _authenticateBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Tap to Unlock'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.2),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).pushReplacementNamed('/login_or_register');
                        }
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Log in with App Account'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2, color: Color(0xFF818CF8)),
                label: 'Library',
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
