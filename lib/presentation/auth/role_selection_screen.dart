import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import 'driver_signup_screen.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.account_circle, size: 80, color: Colors.deepOrange),
              const SizedBox(height: 20),
              const Text(
                'Finalisez votre profil',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Comment souhaitez-vous utiliser Allô Dakar ?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 50),
              
              _buildRoleCard(
                context,
                title: 'Je suis Client',
                subtitle: 'Commander des courses et colis',
                icon: Icons.person_pin,
                color: Colors.orange,
                onTap: () async {
                  final notifier = ref.read(authProvider.notifier);
                  if (ref.read(authProvider) == null) {
                    await notifier.signInAsAnonymousClient();
                  } else {
                    await notifier.setUserRole('client');
                  }
                },
              ),
              
              const SizedBox(height: 20),
              
              _buildRoleCard(
                context,
                title: 'Je suis Chauffeur',
                subtitle: 'Accepter des courses et gagner de l argent',
                icon: Icons.local_taxi,
                color: Colors.black87,
                onTap: () {
                  if (ref.read(authProvider) == null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverSignupScreen()));
                  } else {
                    ref.read(authProvider.notifier).setUserRole('driver');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ],
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
