import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_profile/transen_profile.dart';
import 'package:transen_payment/transen_payment.dart';

final userStreamProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  return ref.watch(userRepositoryProvider).watchUser(userId);
});


class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';
    final isDriver = auth?.role == 'driver';
    
    return Drawer(
      backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1A1A1A),
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
                  context: context,
                  icon: Icons.person_outline,
                  title: 'Mon Profil',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                ),

                if (isDriver) ...[
                  _buildMenuItem(
                    context: context,
                    icon: Icons.history,
                    title: 'Mon Historique',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
                    },
                  ),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.card_giftcard,
                    title: 'Parrainage & Gains',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralScreen()));
                    },
                  ),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Portefeuille TransPay',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    },
                  ),
                ],

                _buildMenuItem(
                  context: context,
                  icon: Icons.support_agent,
                  title: 'Assistance & Contact',
                  onTap: () {
                    Navigator.pop(context);
                    _showAssistanceDialog(context);
                  },
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.settings_outlined,
                  title: 'Paramètres',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),

                const Divider(indent: 20, endIndent: 20),

                _buildMenuItem(
                  context: context,
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
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: AppVersionWidget(
              fontSize: 12,
              color: TranSenColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, String userId, String? role) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final userStream = ref.watch(userStreamProvider(userId));

    return userStream.when(
      data: (userData) {
        String name = userData?['name'] ?? '';
        if (name.isEmpty && userData?['firstName'] != null) {
          name = "${userData!['firstName']} ${userData['lastName'] ?? ''}";
        }
        if (name.isEmpty) {
          name = role == 'driver' ? 'Chauffeur TranSen' : 'Client TranSen';
        }
        
        final String email = userData?['email'] ?? 'Utilisateur';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 60, bottom: 30, left: 25, right: 25),
          decoration: BoxDecoration(
            color: role == 'driver' ? TranSenColors.darkGreen : Theme.of(context).colorScheme.primary,
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
              Consumer(
                builder: (context, ref, child) {
                  final wallet = ref.watch(walletProvider);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          "${wallet.balance.toInt()} FCFA",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }
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
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
          color: role == 'driver' ? TranSenColors.darkGreen : Theme.of(context).colorScheme.primary,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40)),
        ),
        child: Center(
          child: Image.asset('assets/images/logo_menu.png', height: 100),
        ),
      ),
      error: (_, __) => Container(
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
          color: role == 'driver' ? TranSenColors.darkGreen : Theme.of(context).colorScheme.primary,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40)),
        ),
        child: const Center(
          child: Text("Erreur de chargement", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? (isDark ? Colors.white70 : Colors.black87)),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? (isDark ? Colors.white : Colors.black87),
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
        title: const Text('Assistance TranSen'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nous sommes là pour vous aider.'),
            SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.email_outlined, color: Colors.blue, size: 20),
                SizedBox(width: 10),
                Text('contact@transen.sn',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.phone_outlined, color: Colors.green, size: 20),
                SizedBox(width: 10),
                Text('+221 77 000 00 00',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
