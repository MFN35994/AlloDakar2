import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_trips/transen_trips.dart';

class FavoritesSheet extends ConsumerWidget {
  const FavoritesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (auth == null) return const SizedBox.shrink();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("Mes Favoris", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [Tab(text: "Adresses"), Tab(text: "Chauffeurs")],
                    labelColor: TranSenColors.primaryGreen,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: TranSenColors.primaryGreen,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAddressesList(ref, auth.userId),
                        _buildDriversList(ref, auth.userId),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressesList(WidgetRef ref, String userId) {
    final favorites = ref.watch(favoriteAddressesProvider(userId));
    return favorites.when(
      data: (items) {
        if (items.isEmpty) return const Center(child: Text("Aucune adresse favorite"));
        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: Icon(item.icon, color: TranSenColors.primaryGreen),
              title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item.address),
              onTap: () {
                _showAddressActionDialog(context, item.address);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text("Erreur: $e")),
    );
  }

  void _showAddressActionDialog(BuildContext context, String address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Utiliser cette adresse"),
        content: Text(address),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              OrderSheet.show(context, departure: address);
            },
            child: const Text("Départ"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              OrderSheet.show(context, destination: address);
            },
            child: const Text("Destination"),
          ),
        ],
      ),
    );
  }

  Widget _buildDriversList(WidgetRef ref, String userId) {
    final favorites = ref.watch(favoriteDriversProvider(userId));
    return favorites.when(
      data: (items) {
        if (items.isEmpty) return const Center(child: Text("Aucun chauffeur favori"));
        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item.phone),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () {
                Navigator.pop(context);
                OrderSheet.show(context, driverId: item.driverId);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text("Erreur: $e")),
    );
  }
}
