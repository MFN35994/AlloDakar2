import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../core/theme/transen_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth == null) return const Scaffold(body: Center(child: Text("Non connecté")));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Parrainage & Gains'),
        backgroundColor: TranSenColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(auth.userId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String referralCode = data['referralCode'] ?? "TS${auth.userId.substring(0, 4).toUpperCase()}";
          int points = (data['bonusPoints'] ?? 0).toInt();
          int fcfaValue = points * 100;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- SECTION POINTS ---
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [TranSenColors.primaryGreen, TranSenColors.darkGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: TranSenColors.primaryGreen.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8)
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "MES GAINS ACTUELS",
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "$points PTS",
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        "≈ $fcfaValue FCFA",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 20),
                      if (fcfaValue >= 5000)
                        ElevatedButton(
                          onPressed: () => _showRedeemDialog(context, points),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TranSenColors.accentGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          child: const Text("RÉCLAMER MES GAINS", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "Seuil de réclamation : 5000 FCFA",
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
                
                const Text(
                  "Invitez vos amis et gagnez !",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Gagnez 1 point (100 FCFA) pour chaque course effectuée par vos amis parrainés.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                
                const SizedBox(height: 30),
                
                // Card du Code
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "VOTRE CODE DE PARRAINAGE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            referralCode,
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4, color: TranSenColors.primaryGreen),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: referralCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Code copié !"), behavior: SnackBarBehavior.floating),
                              );
                            },
                            icon: const Icon(Icons.copy, color: TranSenColors.primaryGreen),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 25),
                
                ElevatedButton.icon(
                  onPressed: () {
                    Share.share(
                      "🚗 TranSen : Le transport 5 étoiles au Sénégal !\n\nInscris-toi avec mon code parrainage ✨ $referralCode ✨ et gagne des bonus sur tes trajets.\n\n📲 Télécharge l'application maintenant !",
                    );
                  },
                  icon: const Icon(Icons.share),
                  label: const Text("PARTAGER MON CODE"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                
                const SizedBox(height: 40),
                const Text(
                  "Comment ça marche ?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 15),
                _buildStep(Icons.send, "Partagez votre code à vos proches."),
                _buildStep(Icons.person_add, "Ils l'entrent lors de leur inscription."),
                _buildStep(Icons.celebration, "Vous gagnez 100 FCFA à chaque fois qu'ils voyagent !"),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRedeemDialog(BuildContext context, int points) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Réclamer mes points'),
        content: Text('Vous avez $points points (Valeur: ${points * 100} FCFA).\n\nSouhaitez-vous contacter le support pour échanger vos points contre de l\'espèce ou une course gratuite ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = "Bonjour TranSen, je souhaite réclamer mes gains de parrainage ($points points, soit ${points * 100} FCFA).";
              final url = "https://wa.me/221774213939?text=${Uri.encodeComponent(message)}";
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('CONTACTER LE SUPPORT'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: TranSenColors.primaryGreen, size: 18),
          ),
          const SizedBox(width: 15),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
