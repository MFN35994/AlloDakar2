import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Portefeuille'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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

          // Boutons de rechargement
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildRechargeButton(
                  context,
                  'Wave',
                  Colors.lightBlue,
                  Icons.waves,
                ),
                _buildRechargeButton(
                  context,
                  'Orange Money',
                  TranSenColors.primaryGreen,
                  Icons.account_balance_wallet,
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
              final amount = amountController.text.trim();
              if (amount.isEmpty) return;
              
              Navigator.pop(context);
              
              if (method == 'Wave') {
                // Deeplink Wave : ouvre l'app Wave ou le Play Store
                const wavePackage = 'com.wave.personal';
                final waveUrl = Uri.parse('https://play.google.com/store/apps/details?id=$wavePackage');
                try {
                  // Essayer d'ouvrir l'app Wave directement
                  final appUri = Uri.parse('wave://');
                  if (await canLaunchUrl(appUri)) {
                    await launchUrl(appUri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(waveUrl, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {
                  await launchUrl(waveUrl, mode: LaunchMode.externalApplication);
                }
              } else {
                // Orange Money : ouvre l'app OM ou le Play Store
                const omPackage = 'com.orange.money.senegal';
                final omUrl = Uri.parse('https://play.google.com/store/apps/details?id=$omPackage');
                try {
                  final appUri = Uri.parse('orangemoney://');
                  if (await canLaunchUrl(appUri)) {
                    await launchUrl(appUri, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(omUrl, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {
                  await launchUrl(omUrl, mode: LaunchMode.externalApplication);
                }
              }
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Effectuez le transfert de $amount FCFA via $method vers le compte TranSen.'),
                    backgroundColor: color,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('OUVRIR $method'.toUpperCase()),
          ),
        ],
      ),
    );
  }

  Widget _buildRechargeButton(BuildContext context, String name, Color color, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () => _showRechargeDialog(context, name),
      icon: Icon(icon, color: color),
      label: Text(
        name,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey.shade900,
        elevation: 5,
        shadowColor: color.withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}
