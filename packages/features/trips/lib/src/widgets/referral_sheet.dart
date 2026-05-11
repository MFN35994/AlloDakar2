import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:share_plus/share_plus.dart';

class ReferralSheet extends ConsumerWidget {
  const ReferralSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (auth == null) return const SizedBox.shrink();
    
    final referralCode = auth.userId.substring(0, 8).toUpperCase();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          Container(width: 40, height: 5, decoration: BoxDecoration(color: isDark ? Colors.grey[700] : Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 30),
          const Icon(Icons.card_giftcard, size: 64, color: Colors.orange),
          const SizedBox(height: 20),
          Text(
            "Parrainez et gagnez !", 
            style: TextStyle(
              fontSize: 22, 
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Partagez votre code avec vos amis et gagnez 10 points (100 F) pour chaque premier trajet effectué par vos filleuls.",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("VOTRE CODE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
                    Text(
                      referralCode, 
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: 2,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.orange),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: referralCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copié !")));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () {
              Share.share(
                "Rejoins-moi sur TranSen et utilise mon code $referralCode pour tes trajets ! https://transen-pro.web.app",
                subject: "Invitation TranSen",
              );
            },
            icon: const Icon(Icons.share),
            label: const Text("PARTAGER MON CODE"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("PLUS TARD", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
