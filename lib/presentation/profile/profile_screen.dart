import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import '../../data/repositories/user_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: auth?.role == 'driver' ? Colors.black87 : Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: userId.isEmpty 
        ? const Center(child: CircularProgressIndicator())
        : StreamBuilder<Map<String, dynamic>?>(
            stream: ref.read(userRepositoryProvider).watchUser(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              final userData = snapshot.data;
              // Debug pour aider au diagnostic si besoin
              debugPrint("ProfileScreen: UserID=$userId, DataExist=${userData != null}");
              
              String name = userData?['name'] ?? '';
              if (name.isEmpty && userData?['firstName'] != null) {
                name = "${userData!['firstName']} ${userData['lastName'] ?? ''}";
              }
              if (name.isEmpty) {
                // Fallback ultime
                name = auth?.role == 'driver' ? 'Chauffeur Allô Dakar' : 'Client Allô Dakar';
              }
              
              final String email = userData?['email'] ?? 'Non renseigné';
              final String phone = userData?['phone'] ?? (userData?['phoneNumber'] ?? '77 XXX XX XX');
              final bool isVerified = userData?['isVerified'] ?? false;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                            ),
                            child: const CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.white,
                              child: Icon(Icons.person, size: 70, color: Colors.grey),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: auth?.role == 'driver' ? Colors.black : Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    _buildInfoCard('Nom complet', name, Icons.person_outline, trailing: isVerified ? const Icon(Icons.verified, color: Colors.blue, size: 20) : null),
                    _buildInfoCard('Email', email, Icons.email_outlined),
                    _buildInfoCard('Téléphone', phone, Icons.phone_outlined),
                    _buildInfoCard('Rôle', auth?.role.toUpperCase() ?? '', Icons.badge_outlined),
                    
                    if (auth?.role == 'driver' && !isVerified) ...[
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                SizedBox(width: 10),
                                Text("Compte non vérifié", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Pour obtenir le badge 'Vérifié' et attirer plus de passagers, envoyez une photo de votre CNI et de votre Permis sur WhatsApp.",
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              onPressed: () {
                                // Redirection WhatsApp pour la vérification manuelle pour le lancement
                                final whatsappUri = Uri.parse("https://wa.me/221773418501?text=Bonjour, je souhaite vérifier mon compte chauffeur Allô Dakar.");
                                launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
                              },
                              icon: const Icon(Icons.send),
                              label: const Text("VÉRIFIER MES DOCUMENTS"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Fonctionnalité d'édition bientôt disponible !"))
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: auth?.role == 'driver' ? Colors.black87 : Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('MODIFIER LE PROFIL', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
