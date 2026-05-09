import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_rating/transen_rating.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final driverId = auth?.userId ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Note dynamique depuis Firestore
    final ratingAsync = ref.watch(driverRatingProvider(driverId));
    final ratingCountAsync = ref.watch(driverRatingCountProvider(driverId));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: const Text('Mes Statistiques'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
            .collection('trips')
            .where('driverId', isEqualTo: driverId)
            .where('status', isEqualTo: 'completed')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen));
          }

          final trips = snapshot.data?.docs ?? [];
          final double totalEarnings = trips.fold(0.0, (tSum, doc) => tSum + ((doc.data() as Map<String, dynamic>)['price'] ?? 0));
          final int totalTrips = trips.length;

          // Note moyenne dynamique
          final double averageRating = ratingAsync.when(
            data: (value) => value,
            loading: () => 0.0,
            error: (_, __) => 0.0,
          );
          final int ratingCount = ratingCountAsync.when(
            data: (value) => value,
            loading: () => 0,
            error: (_, __) => 0,
          );

          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatCard(
                  context: context,
                  title: 'Gains Totaux',
                  value: '${totalEarnings.toInt()} FCFA',
                  icon: Icons.account_balance_wallet,
                  color: Colors.green,
                ),
                const SizedBox(height: 20),
                _buildStatCard(
                  context: context,
                  title: 'Courses Terminées',
                  value: '$totalTrips',
                  icon: Icons.directions_car,
                  color: Colors.blue,
                ),
                const SizedBox(height: 20),
                _buildStatCard(
                  context: context,
                  title: 'Note Moyenne',
                  value: ratingCount > 0
                      ? '${averageRating.toStringAsFixed(1)} / 5'
                      : 'Pas encore noté',
                  subtitle: ratingCount > 0 ? '$ratingCount avis' : null,
                  icon: Icons.star,
                  color: Colors.amber,
                ),
                const Spacer(),
                Text(
                  'Ces statistiques sont mises à jour en temps réel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade600 : Colors.grey,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.05 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: color.withValues(alpha: isDark ? 0.2 : 0.1)),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade500 : Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
