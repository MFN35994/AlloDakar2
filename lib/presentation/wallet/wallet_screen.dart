import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/wallet_provider.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Portefeuille'),
        backgroundColor: Colors.orange,
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
                  child: Text(
                    '${walletState.balance.toInt()} FCFA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'ALLO DAKAR',
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
                        color: Colors.orange.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Center(
                        child: Text(
                          'PLATINUM',
                          style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),

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
                  Colors.deepOrange,
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

  Widget _buildRechargeButton(BuildContext context, String name, Color color, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () {},
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
