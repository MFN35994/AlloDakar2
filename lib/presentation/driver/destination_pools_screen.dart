import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/pool_model.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/pool_providers.dart';
import '../../data/repositories/trip_repository.dart';
import 'pool_detail_screen.dart';

class DestinationPoolsScreen extends ConsumerStatefulWidget {
  final String destination;
  const DestinationPoolsScreen({super.key, required this.destination});

  @override
  ConsumerState<DestinationPoolsScreen> createState() => _DestinationPoolsScreenState();
}

class _DestinationPoolsScreenState extends ConsumerState<DestinationPoolsScreen> {
  final Set<String> _ignoredPoolIds = {};

  @override
  Widget build(BuildContext context) {
    final poolsAsync = ref.watch(pendingPoolsProvider("ANY|${widget.destination}"));
    final driverId = ref.watch(authProvider)?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text("Demandes pour ${widget.destination}"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: poolsAsync.when(
        data: (pools) {
          final activePools = pools.where((p) => !_ignoredPoolIds.contains(p.id)).toList();
          if (activePools.isEmpty) {
            return const Center(child: Text("Plus de demandes pour cette zone."));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: activePools.length,
            separatorBuilder: (context, index) => const SizedBox(height: 15),
            itemBuilder: (context, index) {
              final pool = activePools[index];
              return _buildPoolEntry(context, pool, driverId);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
        error: (err, _) => Center(child: Text("Erreur: $err")),
      ),
    );
  }

  Widget _buildPoolEntry(BuildContext context, PoolModel pool, String driverId) {
    final isFull = pool.currentFilling >= 4;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.groups, color: Colors.orange),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${pool.departure} ➔ ${pool.destination}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Date: ${pool.scheduledDate}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() => _ignoredPoolIds.add(pool.id)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: pool.currentFilling / 4,
              backgroundColor: Colors.grey.shade200,
              color: pool.currentFilling >= 4 ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${pool.currentFilling} / 4 passagers", style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("${pool.currentFilling * 10000} FCFA potentiels", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        if (pool.currentFilling < 3) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Départ anticipé ?"),
                              content: Text("Il n'y a que ${pool.currentFilling} passager(s). Voulez-vous quand même accepter ?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANNULER")),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OUI")),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                        }

                        // COMMENTÉ POUR LE LANCEMENT GRATUIT
                        // final totalCommission = pool.currentFilling * 500;
                        // final walletBalance = ref.read(walletProvider).balance;
                        // if (walletBalance < totalCommission) {
                        //   throw Exception("Solde insuffisant ($totalCommission FCFA)");
                        // }

                        await ref.read(tripRepositoryProvider).acceptPool(pool.id, driverId);
                        
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PoolDetailScreen(pool: pool)));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFull ? Colors.green : Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text(isFull ? 'ACCEPTER (COMPLET)' : 'ACCEPTER (${pool.currentFilling}/4)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
