import 'dart:async';
import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
                if (auth == null) return;
                final orderId = "D-${DateTime.now().millisecondsSinceEpoch}-${auth.userId}";
                
                messenger.showSnackBar(const SnackBar(content: Text('⏳ Envoi de la demande...')));
                
                final checkoutUrl = await ref.read(paymentRepositoryProvider).createSenePaySession(
                  amount: amount,
                  orderId: orderId,
                  description: "Depot TranSen",
                  customerName: auth.name,
                  customerPhone: auth.phone,
                );

                if (!mounted) return;

                if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('✅ URL reçue ! Ouverture...'), backgroundColor: Colors.green));
                  
                  try {
                    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
                        .collection('users').doc(auth.userId).collection('pending_deposits').doc(orderId).set({
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

  void _showWithdrawDialog(BuildContext context, double balance) {
    final amountController = TextEditingController();
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    String selectedOperator = 'WAVE';
    bool isWithdrawing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Retrait vers Mobile Money', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solde disponible : ${balance.toStringAsFixed(0)} FCFA', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Montant (min 500 FCFA)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: selectedOperator,
                    decoration: const InputDecoration(labelText: 'Opérateur', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'WAVE', child: Text('Wave')),
                      DropdownMenuItem(value: 'ORANGE_MONEY', child: Text('Orange Money')),
                      DropdownMenuItem(value: 'FREE_MONEY', child: Text('Free Money')),
                    ],
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedOperator = val);
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Numéro de téléphone (ex: 771234567)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nom complet du destinataire', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isWithdrawing)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton(
                onPressed: isWithdrawing
                    ? null
                    : () async {
                        final amountText = amountController.text;
                        final amount = double.tryParse(amountText) ?? 0;
                        if (amount < 500) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le montant minimum est de 500 FCFA'), backgroundColor: Colors.red));
                          return;
                        }
                        if (amount > balance) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solde insuffisant'), backgroundColor: Colors.red));
                          return;
                        }
                        if (phoneController.text.isEmpty || nameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez remplir tous les champs'), backgroundColor: Colors.red));
                          return;
                        }

                        setStateDialog(() => isWithdrawing = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);

                        try {
                          final auth = FirebaseAuth.instance.currentUser;
                          if (auth == null) throw Exception("Non connecté");
                          
                          await ref.read(paymentRepositoryProvider).requestPayout(
                            userId: auth.uid,
                            amount: amount,
                            recipientPhone: phoneController.text,
                            recipientName: nameController.text,
                            operator: selectedOperator,
                            description: 'Retrait TranSen',
                          );
                          if (nav.mounted) {
                            nav.pop();
                            messenger.showSnackBar(const SnackBar(content: Text('✅ Retrait initié avec succès !'), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (nav.mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
                            setStateDialog(() => isWithdrawing = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
                child: isWithdrawing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('RETIRER'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String name, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
      label: Text(name, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    );
  }
}
