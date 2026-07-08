import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'firebase_options.dart';

import 'package:neural_canvas/screens/auth_gate.dart';
import 'package:neural_canvas/ui/screens/knowledge_base_screen.dart';
import 'package:neural_canvas/ui/tabs/graph_tab.dart';
import 'package:neural_canvas/ui/tabs/home_tab.dart';
import 'package:neural_canvas/ui/tabs/chat_tab.dart';
import 'package:neural_canvas/screens/chat_history_screen.dart';
import 'package:neural_canvas/services/share_receiver_service.dart';
import 'package:neural_canvas/services/ai_service.dart';
import 'package:neural_canvas/widgets/ai_processing_overlay.dart';
import 'package:neural_canvas/services/notification_service.dart';
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

      // Initialize RevenueCat
      await Purchases.configure(
        PurchasesConfiguration("appl_DIumzQmJmaNDOQiPrfxmrLWixBy"),
      );

      // Sync Customer Info with Firestore
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
            if (kDebugMode) {
              debugPrint("Failed to sync RevenueCat entitlement: $e");
            }
          }
        }
      });
    }

    // Route all framework-level errors straight to telemetry reporting channel
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
          primary: Color(0xFF818CF8), // Indigo 400
          onPrimary: Colors.white,
          secondary: Color(0xFFA78BFA), // Violet 400
          onSecondary: Colors.white,
          surface: Color(0xFF0A0A0E), // Deep background
          onSurface: Color(0xFFF8FAFC), // Slate 50
          surfaceContainerHighest: Color(0xFF1E293B), // Slate 800
          surfaceContainerHigh: Color(0xFF334155), // Slate 700
          surfaceContainerLow: Color(0xFF0B1120), // Slate 950
          outlineVariant: Color(0xFF475569), // Slate 600
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0E), // Deep background
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
    // Begin listening for shared files the absolute second the app boots up
    ShareReceiverService().initialize(navigatorKey);
    globalTabController.addListener(_onTabChanged);

    // A. Listen for incoming files/images while the app is alive in background memory
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleIncomingSharedMedia(value);
      }
    }, onError: (err) {
      print("Axiom Sharing Stream Error: $err");
    });

    // B. Check for files/images if the app was completely terminated and is now cold-launching
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleIncomingSharedMedia(value);
      }
    });



    if (MainRouter.bypassBiometricsOnce) {
      MainRouter.bypassBiometricsOnce = false;
      _navigateToHome();
    } else {
      _authenticateBiometrics();
    }
  }

  void _handleIncomingSharedMedia(List<SharedMediaFile> files) {
    for (var media in files) {
      if (media.type == SharedMediaType.text || media.type == SharedMediaType.url) {
        _handleIncomingSharedText(media.path);
      } else {
        print("Axiom Ingesting File Path: ${media.path}");
        // TODO: Pass 'media.path' (or media.thumbnail) straight into your Asset Import state manager / upload routine.
      }
    }
  }

  void _handleIncomingSharedText(String text) {
    print("Axiom Ingesting Shared Text: $text");
    // TODO: Forward this text block directly into your active workspace scratchpad or call your paste-to-note controller.
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
      // 1. Check device capabilities safely
      bool canCheck = await auth.canCheckBiometrics;
      bool isSupported = await auth.isDeviceSupported();

      // Safety Escape Hatch: If the device doesn't even support biometrics (like a fresh simulator)
      if (!canCheck || !isSupported) {
        debugPrint(
          "Diagnostics: Biometrics not supported on this device. Bypassing lock screen.",
        );
        _navigateToHome();
        return;
      }

      // 2. Trigger the native iOS Face ID prompt
      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please unlock to access your Axiom workspace',
        options: const AuthenticationOptions(
          stickyAuth: false, // Do not let it loop infinitely in the background
          biometricOnly:
              false, // Forces iOS to offer the device PIN/Passcode if Face ID fails
        ),
      );

      if (didAuthenticate) {
        // SUCCESS PATHWAY
        debugPrint("Diagnostics: Biometric authentication successful.");
        _navigateToHome();
      } else {
        // ❌ CRITICAL FIX: Face ID failed or was cancelled by user/reviewer.
        // Do NOT freeze the screen. Force the app to act.
        debugPrint(
          "Diagnostics: Biometrics returned false. Triggering fallback.",
        );

        // Option A: If they are already authenticated via Firebase, let them pass
        if (FirebaseAuth.instance.currentUser != null) {
          _navigateToHome();
        } else {
          // Option B: If not logged in, force clear state and push them to the manual email sheet
          await FirebaseAuth.instance.signOut();
          _navigateToLoginScreen();
        }
      }
    } catch (e) {
      // 🛡️ EMERGENCY ESCAPE HATCH: If any unexpected platform error or timeout occurs
      debugPrint("Diagnostics: Native local auth exception caught: $e");
      _navigateToHome(); // Never block the user or reviewer from entering the app
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
    ShareReceiverService().dispose();
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
