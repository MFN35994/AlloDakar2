
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';



class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : TranSenColors.primaryGreen,
      body: PremiumBackground(
        blobColors: isDarkMode 
          ? [Colors.blue.withValues(alpha: 0.1), Colors.purple.withValues(alpha: 0.1)]
          : [Colors.white.withValues(alpha: 0.2), Colors.greenAccent.withValues(alpha: 0.2)],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Hero(
                  tag: 'auth_icon',
                  child: Icon(Icons.account_circle, 
                    size: 80, 
                    color: isDarkMode ? TranSenColors.primaryGreen : Colors.white),
                ),
                const SizedBox(height: 20),
                Text(
                  'Finalisez votre profil',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'Comment souhaitez-vous utiliser TranSen ?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.white70 : Colors.white.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 50),
                
                _buildRoleCard(
                  context,
                  title: 'Je suis Client',
                  subtitle: 'Commander des courses et colis',
                  icon: Icons.person_pin,
                  color: TranSenColors.primaryGreen,
                  onTap: () async {
                    await HapticFeedback.mediumImpact();
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
                  onTap: () async {
                    await HapticFeedback.mediumImpact();
                    final notifier = ref.read(authProvider.notifier);
                    if (ref.read(authProvider) == null) {
                      // Normalement impossible ici car RoleSelectionScreen requiert un authState
                      await notifier.signInAsAnonymousClient();
                    } else {
                      await notifier.setUserRole('driver');
                    }
                  },
                ),
              ],
            ),
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDarkMode 
                ? Colors.white.withValues(alpha: 0.05) 
                : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDarkMode 
                  ? Colors.white.withValues(alpha: 0.1) 
                  : Colors.white.withValues(alpha: 0.3)
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: isDarkMode ? color.withValues(alpha: 0.1) : TranSenColors.primaryGreen.withValues(alpha: 0.1),
                  child: Icon(icon, color: isDarkMode ? color : TranSenColors.primaryGreen),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, 
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold, 
                          color: isDarkMode ? Colors.white : TranSenColors.primaryGreen
                        )
                      ),
                      Text(subtitle, 
                        style: TextStyle(
                          fontSize: 13, 
                          color: isDarkMode ? Colors.white70 : TranSenColors.primaryGreen.withValues(alpha: 0.7)
                        )
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: isDarkMode ? Colors.white30 : TranSenColors.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
