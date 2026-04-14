import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/wallet_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Historique'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: walletState.transactions.isEmpty
          ? const Center(
              child: Text(
                'Aucune transaction pour le moment.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
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
    );
  }
}
