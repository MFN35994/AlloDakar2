import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import '../../data/repositories/user_repository.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../wallet/history_screen.dart';
import '../profile/referral_screen.dart';
import '../home/trip_tracking_screen.dart';
import '../../domain/providers/trip_providers.dart';

class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';
    
    // Version de l'application (à synchroniser avec pubspec.yaml si possible)
    const String appVersion = 'v1.0.0+1';

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // En-tête Profil
          _buildHeader(context, ref, userId, auth?.role),
          
          const SizedBox(height: 10),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: 'Mon Profil',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.directions_car_filled_outlined,
                  title: 'Mes Courses',
                  onTap: () {
                    Navigator.pop(context);
                    final activeTripAsync = ref.read(activeTripProvider);
                    activeTripAsync.whenData((trip) {
                      if (trip != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TripTrackingScreen(tripId: trip.id),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Vous n'avez aucune course en cours.")),
                        );
                      }
                    });
                  },
                ),
                _buildMenuItem(
                  icon: Icons.support_agent,
                  title: 'Assistance & Contact',
                  onTap: () {
                    Navigator.pop(context);
                    _showAssistanceDialog(context);
                  },
                ),
                _buildMenuItem(
                  icon: Icons.settings_outlined,
                  title: 'Paramètres',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),
                /* COMMENTÉ POUR LE LANCEMENT GRATUIT
                if (auth?.role == 'driver')
                  _buildMenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Mon Portefeuille',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    },
                  ),
                */
                _buildMenuItem(
                  icon: Icons.history,
                  title: 'Mon historique',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.card_giftcard,
                  title: 'Parrainage & Gains',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen()));
                  },
                ),
                const Divider(indent: 20, endIndent: 20),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: 'Déconnexion',
                  titleColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: () async {
                    // On ferme le tiroir avant de se déconnecter
                    Navigator.pop(context);
                    await ref.read(authProvider.notifier).logout();
                  },
                ),
              ],
            ),
          ),
          
          // Version en bas
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'Version $appVersion',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, String userId, String? role) {
    if (userId.isEmpty) return const SizedBox.shrink();
    
    final userStream = ref.watch(StreamProvider((ref) => ref.read(userRepositoryProvider).watchUser(userId)));

    return userStream.when(
      data: (userData) {
        String name = userData?['name'] ?? '';
        if (name.isEmpty && userData?['firstName'] != null) {
          name = "${userData!['firstName']} ${userData['lastName'] ?? ''}";
        }
        if (name.isEmpty) {
          name = role == 'driver' ? 'Chauffeur Allô Dakar' : 'Client Allô Dakar';
        }
        final String email = userData?['email'] ?? 'Utilisateur';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 60, bottom: 30, left: 25, right: 25),
          decoration: BoxDecoration(
            color: role == 'driver' ? Colors.black87 : Colors.orange,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(40),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (userData?['isVerified'] == true) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.verified, color: Colors.blue, size: 20),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              // Email
              Row(
                children: [
                   const Icon(Icons.email_outlined, color: Colors.white70, size: 14),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Text(
                        email,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                     ),
                   ),
                ],
              ),
              const SizedBox(height: 5),
              // Téléphone
              if (userData?['phone'] != null)
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, color: Colors.white70, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      userData!['phone'],
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role == 'driver' ? 'CHAUFFEUR' : 'CLIENT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 200,
        decoration: BoxDecoration(color: role == 'driver' ? Colors.black87 : Colors.orange),
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (_, __) => Container(
        height: 200,
        decoration: BoxDecoration(color: role == 'driver' ? Colors.black87 : Colors.orange),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.black87),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    );
  }

  void _showAssistanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Assistance Allô Dakar'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nous sommes là pour vous aider.'),
            SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.email_outlined, color: Colors.orange, size: 20),
                SizedBox(width: 10),
                Text('allodakar19.sn@gmail.com', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.phone_outlined, color: Colors.green, size: 20),
                SizedBox(width: 10),
                Text('+221 77 000 00 00', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}
