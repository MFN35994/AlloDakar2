import 'dart:async';
import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _handleSync());
  }

  Future<void> _handleSync() async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen');
      final pendingDeps = await db.collection('users').doc(auth.userId).collection('pending_deposits').get();
      if (pendingDeps.docs.isEmpty) return;
      int creditedCount = 0;
      for (var doc in pendingDeps.docs) {
        final success = await ref.read(paymentRepositoryProvider).verifyAndCreditDeposit(auth.userId, doc.id);
        if (success) {
          creditedCount++;
          await doc.reference.delete();
        }
      }
      if (creditedCount > 0) {
        messenger.showSnackBar(SnackBar(content: Text('$creditedCount dépôt(s) crédité(s) !'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Erreur sync auto: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Portefeuille'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () => _handleSync()),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(30),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF000000)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SOLDE TOTAL', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 10),
                    Text('${walletState.balance.toInt()} FCFA', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 15,
                  children: [
                    _buildActionButton(context, 'Déposer', TranSenColors.primaryGreen, Icons.add_circle_outline, () => _showRechargeDialog(context)),
                    _buildActionButton(context, 'Retirer', Colors.redAccent, Icons.outbox, () => _showWithdrawDialog(context, walletState.balance)),
                  ],
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: TranSenColors.primaryGreen),
                        SizedBox(height: 15),
                        Text("Connexion SenePay...", style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 5),
                        Text("Veuillez patienter (max 1 min)", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showRechargeDialog(BuildContext context) {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recharger mon compte'),
        content: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant (FCFA)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount < 100) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              final messenger = ScaffoldMessenger.of(context);
              
              try {
                final auth = ref.read(authProvider);
                final orderId = "D-${DateTime.now().millisecondsSinceEpoch}";
                
                messenger.showSnackBar(const SnackBar(content: Text('⏳ Envoi de la demande...')));
                
                final checkoutUrl = await ref.read(paymentRepositoryProvider).createSenePaySession(
                  amount: amount,
                  orderId: orderId,
                  description: "Depot TranSen",
                  customerName: auth?.name,
                  customerPhone: auth?.phone,
                );

                if (!mounted) return;

                if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('✅ URL reçue ! Ouverture...'), backgroundColor: Colors.green));
                  
                  try {
                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
                        .collection('users').doc(auth!.userId).collection('pending_deposits').doc(orderId).set({
                      'amount': amount, 'method': 'SenePay', 'status': 'Pending', 'createdAt': FieldValue.serverTimestamp(),
                    });
                  } catch (fsErr) {
                    debugPrint('>>> Firestore save pending deposit error: $fsErr');
                    // On ne bloque pas l'ouverture de l'URL même si Firebase refuse l'écriture (règles de sécurité)
                  }

                  final uri = Uri.parse(checkoutUrl);
                  try {
                    await launchUrl(uri);
                  } catch (launchErr) {
                    messenger.showSnackBar(SnackBar(content: Text('❌ Impossible d\'ouvrir le lien. Erreur: $launchErr'), backgroundColor: Colors.orange));
                  }
                } else {
                  messenger.showSnackBar(const SnackBar(content: Text('❌ Pas de réponse du serveur.'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (mounted) messenger.showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('PAYER'),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double balance) {}

  Widget _buildActionButton(BuildContext context, String name, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
      label: Text(name, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    );
  }
}
