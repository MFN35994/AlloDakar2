import 'package:flutter/material.dart';
import '../../core/theme/transen_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/trip_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DriverReviewsSheet extends ConsumerWidget {
  final String driverId;
  final String driverName;

  const DriverReviewsSheet({
    super.key, 
    required this.driverId, 
    required this.driverName
  });

  static void show(BuildContext context, String driverId, String driverName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DriverReviewsSheet(driverId: driverId, driverName: driverName),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(driverReviewsProvider(driverId));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey.shade900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.stars, color: TranSenColors.primaryGreen, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Avis pour $driverName",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        "Ce que disent les autres clients",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: reviewsAsync.when(
              data: (reviews) {
                if (reviews.isEmpty) {
                  return const Center(
                    child: Text("Aucun avis pour le moment."),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    final review = reviews[index];
                    final rating = review['rating'] as int? ?? 0;
                    final comment = review['comment'] as String? ?? '';
                    final userName = review['userName'] as String? ?? 'Client';
                    final timestamp = (review['createdAt'] as Timestamp?)?.toDate();
                    final dateStr = timestamp != null ? DateFormat('dd/MM/yyyy').format(timestamp) : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                userName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TranSenColors.primaryGreen),
                              ),
                              const Spacer(),
                              Text(
                                dateStr,
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: List.generate(5, (i) => Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 14,
                            )),
                          ),
                          if (comment.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              comment,
                              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen)),
              error: (e, _) => Center(child: Text("Erreur: $e")),
            ),
          ),
        ],
      ),
    );
  }
}
