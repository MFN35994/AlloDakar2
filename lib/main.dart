import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'presentation/splash/splash_screen.dart';
import 'data/services/notification_service.dart';
import 'domain/providers/theme_provider.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/role_selection_screen.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/driver/driver_home_screen.dart';
import 'domain/providers/auth_provider.dart';
import 'core/theme/transen_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

// 1. Initialisation de App Check (Optimisée avec const)
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidDebugProvider(),
      providerApple: const AppleDebugProvider(),
    );
    FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
        .settings = const Settings(persistenceEnabled: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    NotificationService.listenToMessages();
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'TranSen',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: TranSenColors.primaryGreen,
          onPrimary: Colors.white,
          secondary: TranSenColors.accentGold,
          surface: TranSenColors.backgroundWhite,
          onSurface: TranSenColors.textDark,
        ),
        scaffoldBackgroundColor: TranSenColors.backgroundWhite,
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: TranSenColors.primaryGreen,
          onPrimary: Colors.white,
          secondary: TranSenColors.accentGold,
          surface: Color(0xFF1A1A1A),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context)
              .textTheme
              .apply(bodyColor: Colors.white, displayColor: Colors.white),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On écoute le provider d'authentification
    final authState = ref.watch(authProvider);

    // Cas 1 : L'état est nul (Utilisateur non connecté)
    if (authState == null) {
      return const LoginScreen();
    }

    // Cas 2 : On utilise notre méthode .when() personnalisée de AuthState
    return authState.when(
      // Si les données sont prêtes (isLoading est false)
      data: (auth) {
        // Redirection selon le rôle stocké dans Firestore
        if (auth.role == 'driver') {
          return const DriverHomeScreen();
        } else if (auth.role == 'client') {
          return const HomeScreen();
        } else {
          // Si le rôle n'est pas encore défini (première connexion)
          return const RoleSelectionScreen();
        }
      },
      // Si le notifier est en train de fetch le rôle ou d'envoyer un code
      loading: () => const SplashScreen(),
      // En cas d'erreur critique
      error: (e, stack) => Scaffold(
        body: Center(
          child: Text(
            "Erreur d'authentification : $e",
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
