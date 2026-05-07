import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: auth?.role == 'driver' ? Colors.black87 : TranSenColors.primaryGreen,
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
                name = auth?.role == 'driver' ? 'Chauffeur TranSen' : 'Client TranSen';
              }
              
              String phone = userData?['phone'] ?? (userData?['phoneNumber'] ?? '');
              if (phone.trim() == '+221' || phone.trim().isEmpty || phone.trim().length <= 4) {
                final fbUser = FirebaseAuth.instance.currentUser;
                if (fbUser?.phoneNumber != null && fbUser!.phoneNumber!.length > 4) {
                  phone = fbUser.phoneNumber!;
                } else if (auth?.phone != null && auth!.phone!.length > 4) {
                  phone = auth.phone!;
                } else {
                  phone = 'Non renseigné';
                }
              }
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
                                color: auth?.role == 'driver' ? Colors.black : TranSenColors.primaryGreen,
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
                                Icon(Icons.warning_amber_rounded, color: TranSenColors.primaryGreen),
                                SizedBox(width: 10),
                                Text("Compte non vérifié", style: TextStyle(fontWeight: FontWeight.bold, color: TranSenColors.primaryGreen)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Le module de vérification des documents (CNI, Permis) est en cours de construction. Vous pourrez bientôt télécharger vos documents directement dans l'application.",
                              style: TextStyle(fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Fonctionnalité en cours de développement..."),
                                    backgroundColor: TranSenColors.primaryGreen,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.construction),
                              label: const Text("VÉRIFICATION BIENTÔT DISPONIBLE"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: TranSenColors.primaryGreen,
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
                        onPressed: () => _showEditPhoneDialog(context, ref, userId, phone),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: auth?.role == 'driver' ? Colors.black87 : TranSenColors.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('MODIFIER LE NUMÉRO', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  void _showEditPhoneDialog(BuildContext context, WidgetRef ref, String userId, String currentPhone) {
    final controller = TextEditingController(text: currentPhone == 'Non renseigné' ? '' : currentPhone);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le numéro'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Nouveau numéro',
            hintText: '77 123 45 67',
            prefixText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          ElevatedButton(
            onPressed: () async {
              String input = controller.text.trim().replaceAll(' ', '');
              String digitsOnly = input.replaceAll(RegExp(r'\D'), '');
              
              // Normalisation Sénégal
              String finalPhone = digitsOnly;
              if (finalPhone.startsWith('221') && finalPhone.length >= 12) {
                finalPhone = finalPhone.substring(3);
              }

              if (finalPhone.length < 9) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Numéro invalide (min 9 chiffres)")),
                );
                return;
              }

              try {
                await ref.read(userRepositoryProvider).updateUserData(userId, {
                  'phone': finalPhone,
                  'phoneNumber': finalPhone, 
                });
                if (context.mounted) Navigator.pop(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Numéro mis à jour avec succès !"), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Erreur : ${e.toString()}"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('ENREGISTRER'),
          ),
        ],
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
