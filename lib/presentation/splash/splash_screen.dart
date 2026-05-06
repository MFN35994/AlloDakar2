import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:transen_auth/transen_auth.dart';
import '../home/home_screen.dart';
import '../driver/driver_home_screen.dart';
import 'package:transen_core/transen_core.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Timer(const Duration(seconds: 3), () {
      _checkAuthAndNavigate();
    });
  }

  void _checkAuthAndNavigate() {
    if (!mounted) return;
    
    final auth = ref.read(authProvider);
    if (auth == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      // Si on attend encore le rôle, on attend un peu
      if (auth.isLoading) {
        Timer(const Duration(milliseconds: 500), _checkAuthAndNavigate);
        return;
      }
      
      Widget nextScreen;
      if (auth.role == 'none') {
        nextScreen = const RoleSelectionScreen();
      } else if (auth.role == 'driver') {
        nextScreen = const DriverHomeScreen();
      } else {
        nextScreen = const HomeScreen();
      }
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => nextScreen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 180,
              height: 180,
            ),
            const SizedBox(height: 30),
            const Text(
              'TranSen',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: TranSenColors.primaryGreen,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Transport & Livraison',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
