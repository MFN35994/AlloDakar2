import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'presentation/splash/splash_screen.dart';
import 'data/services/notification_service.dart';
import 'domain/providers/theme_provider.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/role_selection_screen.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/driver/driver_home_screen.dart';
import 'domain/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    
    // Configurer le gestionnaire de messages en arrière-plan
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    // Écouter les messages au premier plan
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
      title: 'Allô Dakar',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Colors.orange.shade800,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.grey.shade900,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.orange.shade800,
          onPrimary: Colors.white,
          surface: const Color(0xFF1A1A1A),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
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
    final auth = ref.watch(authProvider);

    if (auth == null) {
      return const LoginScreen();
    }

    if (auth.isLoading) {
      return const SplashScreen();
    }

    if (auth.role == 'none') {
      return const RoleSelectionScreen();
    } else if (auth.role == 'driver') {
      return const DriverHomeScreen();
    } else {
      return const HomeScreen();
    }
  }
}
