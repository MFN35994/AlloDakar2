import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/wallet_provider.dart';
import '../../domain/providers/auth_provider.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../core/theme/transen_colors.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final walletState = ref.watch(walletProvider);
    final tripRepo = ref.watch(tripRepositoryProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Mon Historique'),
          backgroundColor: TranSenColors.primaryGreen,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.payments), text: "Transactions"),
              Tab(icon: Icon(Icons.directions_car), text: "Trajets"),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: [
            // Onglet Transactions
            _buildTransactionsList(context, walletState),
            
            // Onglet Trajets
            _buildTripsList(context, tripRepo, auth?.userId ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context, walletState) {
    if (walletState.transactions.isEmpty) {
      return const Center(
        child: Text(
          'Aucune transaction pour le moment.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: walletState.transactions.length,
      itemBuilder: (context, index) {
        final txn = walletState.transactions[index];
        final isDebit = txn.amount < 0;
        final isPoints = txn.points > 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
          color: Colors.grey.shade50,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPoints 
                  ? Colors.amber.withValues(alpha: 0.1)
                  : (isDebit ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1)),
              child: Icon(
                isPoints ? Icons.stars : (isDebit ? Icons.arrow_outward : Icons.arrow_downward),
                color: isPoints ? Colors.amber : (isDebit ? Colors.red : Colors.green),
              ),
            ),
            title: Text(txn.description, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              '${txn.date.day}/${txn.date.month}/${txn.date.year} à ${txn.date.hour}:${txn.date.minute.toString().padLeft(2, "0")}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              isPoints 
                  ? '+${txn.points} pts'
                  : '${isDebit ? "" : "+"}${txn.amount.toInt()} FCFA',
              style: TextStyle(
                color: isPoints ? Colors.amber.shade700 : (isDebit ? Colors.red : Colors.green),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTripsList(BuildContext context, TripRepository repo, String userId) {
    return StreamBuilder<List<TripModel>>(
      stream: repo.watchUserTrips(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final trips = snapshot.data ?? [];
        if (trips.isEmpty) {
          return const Center(
            child: Text(
              'Aucun trajet terminé.',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: trips.length,
          itemBuilder: (context, index) {
            final trip = trips[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 0,
              color: Colors.grey.shade50,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                  child: const Icon(Icons.location_on, color: TranSenColors.primaryGreen),
                ),
                title: Text("${trip.departure} ➔ ${trip.destination}", 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                  '${trip.createdAt.day}/${trip.createdAt.month}/${trip.createdAt.year} • ${trip.type}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("TERMINÉ", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
