import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/providers/auth_provider.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth == null) return const Scaffold(body: Center(child: Text("Non connecté")));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parrainage & Gains'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(auth.userId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String? referralCode = data['referralCode'];
          
          // Générer un code si inexistant
          if (referralCode == null || referralCode.isEmpty) {
            referralCode = auth.userId.substring(0, 6).toUpperCase();
            FirebaseFirestore.instance.collection('users').doc(auth.userId).update({
              'referralCode': referralCode,
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.card_giftcard, size: 100, color: Colors.orange),
                const SizedBox(height: 20),
                const Text(
                  "Invitez vos amis et gagnez des cadeaux !",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                const Text(
                  "Partagez votre code de parrainage. Pour chaque ami qui s'inscrit, vous recevrez un bonus sur votre prochain trajet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),
                
                // Card du Code
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Column(
                    children: [
                      const Text("VOTRE CODE"),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            referralCode,
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: referralCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Code copié !")),
                              );
                            },
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                ElevatedButton.icon(
                  onPressed: () {
                    Share.share(
                      "🚗 Allô Dakar : Le transport 5 étoiles au Sénégal !\n\nInscris-toi avec mon code parrainage ✨ $referralCode ✨ et profite de réductions sur tes trajets.\n\n📲 Demande-moi l'APK pour l'installer maintenant et commence à voyager !",
                    );
                  },
                  icon: const Icon(Icons.share),
                  label: const Text("PARTAGER MON CODE"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
                
                const SizedBox(height: 40),
                const Text(
                  "Comment ça marche ?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 15),
                _buildStep(Icons.send, "Envoyez votre lien à vos proches."),
                _buildStep(Icons.person_add, "Ils s'inscrivent avec votre code."),
                _buildStep(Icons.celebration, "Vous recevez tous les deux un bonus !"),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 20),
          const SizedBox(width: 15),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
