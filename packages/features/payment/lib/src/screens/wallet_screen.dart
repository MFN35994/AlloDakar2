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
  @override
  void initState() {
    super.initState();
    // Lancer la synchronisation automatique au chargement
    Future.microtask(() => _handleSync());
  }

  Future<void> _handleSync() async {
    final auth = ref.read(authProvider);
    if (auth == null) return;
    
    try {
      final pendingDeps = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
          .collection('users')
          .doc(auth.userId)
          .collection('pending_deposits')
          .get();

      if (pendingDeps.docs.isEmpty) return;

      int creditedCount = 0;
      for (var doc in pendingDeps.docs) {
        final orderId = doc.id;
        final success = await ref.read(paymentRepositoryProvider).verifyAndCreditDeposit(auth.userId, orderId);
        if (success) {
          creditedCount++;
          await doc.reference.delete();
        }
      }

      if (mounted && creditedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$creditedCount dépôt(s) crédité(s) automatiquement !'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Actualiser le solde',
            onPressed: () => _handleSync(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Solde actuel - Platinum Card
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(30),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C3E50), Color(0xFF000000)], // Noir Premium
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Solde Disponible',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Icon(Icons.contactless, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedCountText(
                    value: walletState.balance.toInt(),
                    suffix: ' FCFA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Text(
                      'TRANSEN',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 50,
                      height: 25,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: Text(
                          'PLATINUM',
                          style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),

          // --- SECTION PARRAINAGE & POINTS ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.stars, color: Colors.amber, size: 28),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mes Points',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              '1 pt = 100 FCFA',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AnimatedCountText(
                          value: walletState.points.toInt(),
                          suffix: ' pts',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900, 
                            fontSize: 22, 
                            color: Colors.amber
                          ),
                        ),
                        AnimatedCountText(
                          value: (walletState.points * 100).toInt(),
                          suffix: ' FCFA',
                          style: const TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            color: Colors.grey
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mon Code Parrainage',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          Consumer(builder: (context, ref, child) {
                            final auth = ref.watch(authProvider);
                            return FutureBuilder<String>(
                              future: UserRepository().ensureReferralCode(auth?.userId ?? ''),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? '...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    letterSpacing: 2,
                                    color: TranSenColors.primaryGreen
                                  ),
                                );
                              }
                            );
                          }),
                        ],
                      ),
                    ),
                    if (walletState.points * 100 >= 5000)
                      ElevatedButton(
                        onPressed: () {
                          _showRedeemDialog(context, walletState.points.toInt());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('RÉCLAMER', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Dès 5000 FCFA',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Boutons d'actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _buildActionButton(
                  context,
                  'Déposer (Wave)',
                  Colors.lightBlue,
                  Icons.add_circle_outline,
                  () => _showRechargeDialog(context, 'Wave'),
                ),
                _buildActionButton(
                  context,
                  'Déposer (OM)',
                  TranSenColors.primaryGreen,
                  Icons.add_circle_outline,
                  () => _showRechargeDialog(context, 'Orange Money'),
                ),
                _buildActionButton(
                  context,
                  'Retirer',
                  Colors.redAccent,
                  Icons.outbox,
                  () => _showWithdrawDialog(context, walletState.balance),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),

          // Titre Historique
          const Padding(
            padding: EdgeInsets.only(left: 20.0, top: 10, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Historique des Transactions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Liste des transactions
          Expanded(
            child: walletState.transactions.isEmpty
                ? const Center(
                    child: Text(
                      'Aucune transaction pour le moment.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: walletState.transactions.length,
                    itemBuilder: (context, index) {
                      final txn = walletState.transactions[index];
                      final isDebit = txn.amount < 0;
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isDebit 
                              ? Colors.red.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.1 : 0.2) 
                              : Colors.green.withValues(alpha: Theme.of(context).brightness == Brightness.light ? 0.1 : 0.2),
                          child: Icon(
                            isDebit ? Icons.arrow_outward : Icons.arrow_downward,
                            color: isDebit ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(txn.description),
                        subtitle: Text(
                          '${txn.date.day}/${txn.date.month}/${txn.date.year} à ${txn.date.hour}:${txn.date.minute.toString().padLeft(2, '0')}',
                        ),
                        trailing: Text(
                          '${isDebit ? '' : '+'}${txn.amount.toInt()} FCFA',
                          style: TextStyle(
                            color: isDebit ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showRedeemDialog(BuildContext context, int points) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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

  void _showRechargeDialog(BuildContext context, String method) {
    final amountController = TextEditingController();
    final Color color = method == 'Wave' ? Colors.lightBlue : TranSenColors.primaryGreen;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              method == 'Wave' ? Icons.waves : Icons.account_balance_wallet,
              color: color,
            ),
            const SizedBox(width: 10),
            Text('Recharger via $method'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Entrez le montant à recharger. Vous serez redirigé vers l\'application $method.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Montant (FCFA)',
                prefixIcon: Icon(Icons.monetization_on, color: color),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: color, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ANNULER'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amountStr = amountController.text.trim();
              if (amountStr.isEmpty) return;
              final amount = double.tryParse(amountStr) ?? 0;
              if (amount < 100) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le montant minimum est de 100 FCFA.')));
                 return;
              }

              Navigator.pop(context);
              
              // Afficher loader
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen)),
              );

              try {
                final auth = ref.read(authProvider);
                final orderId = "DEP-${DateTime.now().millisecondsSinceEpoch}-${auth?.userId}";
                
                final checkoutUrl = await ref.read(paymentRepositoryProvider).createSenePaySession(
                  amount: amount,
                  orderId: orderId,
                  description: "Dépôt Portefeuille TransPay via $method",
                  customerName: auth?.name,
                  customerPhone: auth?.phone,
                  providerId: method == 'Wave' ? 'WAVE' : 'ORANGE_MONEY',
                );

                if (context.mounted) Navigator.pop(context); // Enlever loader

                if (checkoutUrl != null) {
                  // Sauvegarder le dépôt en attente
                  await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
                      .collection('users')
                      .doc(auth!.userId)
                      .collection('pending_deposits')
                      .doc(orderId)
                      .set({
                    'amount': amount,
                    'method': method,
                    'status': 'Pending',
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  final uri = Uri.parse(checkoutUrl);
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    debugPrint("Erreur launchUrl: $e");
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Impossible d\'ouvrir le lien de paiement. Veuillez copier ce lien : $checkoutUrl'), duration: const Duration(seconds: 10))
                      );
                    }
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Impossible de générer le lien de paiement. Réessayez plus tard.'))
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Enlever loader au cas où
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('PAYER AVEC $method'.toUpperCase()),
          ),
        ],
      ),
    );
  }

  void _showWithdrawDialog(BuildContext context, double balance) {
    if (balance < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le montant minimum pour un retrait est de 500 FCFA.'))
      );
      return;
    }

    final amountController = TextEditingController();
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    String selectedOperator = 'WAVE';
    bool isProcessing = false;

    // Pré-remplir le téléphone si possible
    final auth = ref.read(authProvider);
    if (auth?.phone != null) {
      phoneController.text = auth!.phone!.replaceAll(RegExp(r'\D'), '');
      if (phoneController.text.startsWith('221') && phoneController.text.length >= 12) {
        phoneController.text = phoneController.text.substring(3);
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.account_balance, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Retirer mes gains'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Solde disponible : ${balance.toInt()} FCFA',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: TranSenColors.primaryGreen),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Montant à retirer',
                    suffixText: 'FCFA',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Numéro de réception',
                    prefixText: '+221 ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Nom du bénéficiaire',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: selectedOperator,
                  decoration: InputDecoration(
                    labelText: 'Opérateur',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'WAVE', child: Text('Wave')),
                    DropdownMenuItem(value: 'ORANGE_MONEY', child: Text('Orange Money')),
                    DropdownMenuItem(value: 'FREE_MONEY', child: Text('Free Money')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedOperator = val!),
                ),
                if (isProcessing)
                  const Padding(
                    padding: EdgeInsets.all(15.0),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('ANNULER'),
            ),
            ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final amountStr = amountController.text.trim();
                final phone = phoneController.text.trim();
                final name = nameController.text.trim();

                if (amountStr.isEmpty || phone.isEmpty || name.isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez remplir tous les champs.')));
                   return;
                }

                final amount = double.tryParse(amountStr) ?? 0;
                if (amount < 500 || amount > balance) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Montant invalide (min 500, max solde).')));
                   return;
                }

                setDialogState(() => isProcessing = true);

                try {
                  final result = await ref.read(paymentRepositoryProvider).requestPayout(
                    userId: auth!.userId,
                    amount: amount,
                    recipientPhone: "221$phone",
                    recipientName: name,
                    operator: selectedOperator,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    if (result != null) {
                      SuccessDialog.show(
                        context,
                        title: 'Retrait initié !',
                        message: 'Votre demande de retrait de ${amount.toInt()} FCFA est en cours de traitement.',
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Échec de la demande. Veuillez réessayer.')));
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    setDialogState(() => isProcessing = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('RETIRER'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String name, Color color, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 20),
      label: Text(
        name,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey.shade900,
        elevation: 2,
        shadowColor: color.withValues(alpha: 0.2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}
