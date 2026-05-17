import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/splash/splash_screen.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/driver/driver_home_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'src/generated/l10n/app_localizations.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Settings;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation de Mapbox
  const String mapboxToken = "pk.eyJ1IjoidHJhbnNlbiIsImEiOiJjbXA4Nm5menUwM205MnNwOGZmb3N3ZTM4In0.SMFaXkbJJi5bM6Bk3_p8ng";
  MapboxOptions.setAccessToken(mapboxToken);

  final prefs = await SharedPreferences.getInstance();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

// 1. Initialisation de App Check (Adaptée pour la Production)
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
      providerApple: kReleaseMode ? const AppleAppAttestProvider() : const AppleDebugProvider(),
    );
    FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
        .settings = const Settings(persistenceEnabled: !kIsWeb);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    NotificationService.listenToMessages();
  } catch (e) {
    debugPrint("Firebase init failed: $e");
  }
  runApp(
    ProviderScope(
      overrides: [
        localeProvider.overrideWith(() => LocaleNotifier()..init(prefs)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'TranSen',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr'),
      ],
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
        scaffoldBackgroundColor: Color(0xFF121212),
        useMaterial3: true,
        textTheme: GoogleFonts.montserratTextTheme(
          Theme.of(context)
              .textTheme
              .apply(bodyColor: Colors.white, displayColor: Colors.white),
        ),
      ),
      home: const InitialGate(),
    );
  }
}

class InitialGate extends StatefulWidget {
  const InitialGate({super.key});

  @override
  State<InitialGate> createState() => _InitialGateState();
}

class _InitialGateState extends State<InitialGate> {
  bool? _seenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _seenOnboarding = prefs.getBool('onboarding_seen') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_seenOnboarding == null) return const SplashScreen();
    if (_seenOnboarding == false) return const OnboardingScreen();
    return const AuthGate();
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On écoute le provider d'authentification
    final authState = ref.watch(authProvider);

    // Cas 1 : L'état est nul ou vide (Utilisateur non connecté ou en cours de saisie OTP)
    if (authState == null || authState.userId.isEmpty) {
      return const LoginScreen();
    }

    // Cas 2 : On utilise notre méthode .when() personnalisée de AuthState
    return authState.when(
      // Si les données sont prêtes (isLoading est false)
      data: (auth) {
        // Si le profil est incomplet (pas de nom), on reste sur LoginScreen (étape Identity)
        if (auth.name == null || auth.name!.isEmpty) {
          return const LoginScreen();
        }

        // Initialiser les notifications push pour cet utilisateur
        NotificationService().init(auth.userId);

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
