import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/providers/auth_provider.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final driverId = auth?.userId ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mes Statistiques'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('trips')
            .where('driverId', isEqualTo: driverId)
            .where('status', isEqualTo: 'accepted') // On considère 'accepted' car on n'a pas encore de bouton "Terminer"
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
          }

          final trips = snapshot.data?.docs ?? [];
          final double totalEarnings = trips.fold(0.0, (tSum, doc) => tSum + (doc.data() as Map<String, dynamic>)['price']);
          final int totalTrips = trips.length;

          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatCard(
                  title: 'Gains Totaux',
                  value: '${totalEarnings.toInt()} FCFA',
                  icon: Icons.account_balance_wallet,
                  color: Colors.green,
                ),
                const SizedBox(height: 20),
                _buildStatCard(
                  title: 'Courses Effectuées',
                  value: '$totalTrips',
                  icon: Icons.directions_car,
                  color: Colors.blue,
                ),
                const SizedBox(height: 20),
                _buildStatCard(
                  title: 'Note Moyenne',
                  value: '4.9 / 5',
                  icon: Icons.star,
                  color: Colors.amber,
                ),
                const Spacer(),
                const Text(
                  'Ces statistiques sont mises à jour en temps réel après chaque course acceptée.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }
}
