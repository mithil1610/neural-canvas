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
    globalTabController.addListener(_onTabChanged);

    // A. Listen for incoming files/images while the app is alive in background memory
    ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleIncomingSharedMedia(value);
        }
      },
      onError: (err) {
        if (kDebugMode) debugPrint("Axiom Sharing Stream Error: $err");
      },
    );

    // B. Check for files/images if the app was completely terminated and is now cold-launching
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
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

  // Graceful warning popup for unsupported file profiles
  void _showUnsupportedTypeDialog(String fileType) {
    final targetContext = navigatorKey.currentContext;
    if (targetContext == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: targetContext,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B), // Slate 800
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Color(0xFFA78BFA),
                  size: 28,
                ), // Violet 400
                SizedBox(width: 12),
                Text(
                  'Invalid File Type',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              'Axiom cannot process files with the extension [ .$fileType ]. Please make sure you are sharing eligible images, screenshots, text files, or PDFs.',
              style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                ), // Indigo 400
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    });
  }

  void _handleIncomingSharedMedia(List<SharedMediaFile> files) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (var media in files) {
      final String rawPath = media.path;
      final String fileExtension = rawPath.contains('.')
          ? rawPath.split('.').last.toLowerCase()
          : '';

      // Format Validation Matrix
      final bool isEligibleImage =
          media.type == SharedMediaType.image ||
          ['jpg', 'jpeg', 'png', 'gif', 'heic', 'webp'].contains(fileExtension);

      final bool isEligibleDoc = [
        'pdf',
        'doc',
        'docx',
        'txt',
        'rtf',
      ].contains(fileExtension);

      // Validation Gatekeeper: Terminate parsing if an incompatible file profile is caught
      if (!isEligibleImage &&
          !isEligibleDoc &&
          media.type != SharedMediaType.text &&
          media.type != SharedMediaType.url) {
        if (kDebugMode)
          debugPrint("Axiom Blocked Unsupported Type: .$fileExtension");
        _showUnsupportedTypeDialog(fileExtension.toUpperCase());
        continue;
      }

      if (media.type == SharedMediaType.text ||
          media.type == SharedMediaType.url) {
        _handleIncomingSharedText(media.path);
      } else {
        // Active Ingestion: Differentiate images from documents during the Firestore synchronization routine
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('knowledge_base')
              .add({
                'title': isEligibleImage
                    ? 'Shared Image Asset'
                    : 'Shared Document Asset',
                'type': isEligibleImage ? 'image' : 'document',
                'path': rawPath,
                'createdAt': FieldValue.serverTimestamp(),
              });

          if (kDebugMode)
            debugPrint("Axiom Successfully Imported Share Asset: $rawPath");

          // Switch view context directly over to the Library Tab (Index 1)
          globalTabController.value = 1;
        } catch (e) {
          if (kDebugMode)
            debugPrint("Failed to write share asset to Firestore: $e");
        }
      }
    }
  }

  void _handleIncomingSharedText(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('knowledge_base')
          .add({
            'title': 'Shared Clip Note',
            'type': 'text',
            'content': text,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (kDebugMode) debugPrint("Axiom Successfully Pasted Shared Text.");
      globalTabController.value = 1;
    } catch (e) {
      if (kDebugMode) debugPrint("Failed to write share text to Firestore: $e");
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
        debugPrint(
          "Diagnostics: Biometrics not supported on this device. Bypassing lock screen.",
        );
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
        debugPrint("Diagnostics: Biometric authentication successful.");
        _navigateToHome();
      } else {
        debugPrint(
          "Diagnostics: Biometrics returned false. Triggering fallback.",
        );

        if (FirebaseAuth.instance.currentUser != null) {
          _navigateToHome();
        } else {
          await FirebaseAuth.instance.signOut();
          _navigateToLoginScreen();
        }
      }
    } catch (e) {
      debugPrint("Diagnostics: Native local auth exception caught: $e");
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
