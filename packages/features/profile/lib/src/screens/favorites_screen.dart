import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_trips/transen_trips.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final userId = auth?.userId ?? '';
    final favoritesAsync = ref.watch(favoriteAddressesProvider(userId));
    final driversAsync = ref.watch(favoriteDriversProvider(userId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
        appBar: AppBar(
          title: const Text('Mes Favoris'),
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : TranSenColors.primaryGreen,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.place), text: "Adresses"),
              Tab(icon: Icon(Icons.person), text: "Chauffeurs"),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            _buildAddressesList(context, ref, userId, favoritesAsync),
            _buildDriversList(context, ref, userId, driversAsync),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddAddressDialog(context, ref, userId),
          backgroundColor: TranSenColors.primaryGreen,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildAddressesList(BuildContext context, WidgetRef ref, String userId, AsyncValue<List<FavoriteAddress>> async) {
    return async.when(
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('Aucune adresse favorite.', style: TextStyle(color: Colors.grey)));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final addr = list[index];
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                leading: Icon(addr.icon, color: TranSenColors.primaryGreen),
                title: Text(addr.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(addr.address),
                onTap: () {
                  Navigator.pop(context);
                  OrderSheet.show(context, destination: addr.address);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => ref.read(favoritesRepositoryProvider).removeFavoriteAddress(userId, addr.id),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
    );
  }

  Widget _buildDriversList(BuildContext context, WidgetRef ref, String userId, AsyncValue<List<FavoriteDriver>> async) {
    return async.when(
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('Aucun chauffeur favori.', style: TextStyle(color: Colors.grey)));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final driver = list[index];
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: TranSenColors.primaryGreen, child: Icon(Icons.person, color: Colors.white)),
                title: Text(driver.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(driver.phone),
                onTap: () {
                  Navigator.pop(context);
                  OrderSheet.show(context, driverId: driver.driverId);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => ref.read(favoritesRepositoryProvider).removeFavoriteDriver(userId, driver.driverId),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
    );
  }

  void _showAddAddressDialog(BuildContext context, WidgetRef ref, String userId) {
    final labelController = TextEditingController();
    final addressController = TextEditingController();
    String selectedIcon = 'home';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter une adresse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: labelController, decoration: const InputDecoration(labelText: 'Nom (ex: Maison, Travail)')),
            TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Région / Adresse')),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedIcon,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'home', child: Text('Maison')),
                DropdownMenuItem(value: 'work', child: Text('Travail')),
                DropdownMenuItem(value: 'favorite', child: Text('Favori')),
                DropdownMenuItem(value: 'location', child: Text('Autre')),
              ],
              onChanged: (val) => selectedIcon = val ?? 'home',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER')),
          ElevatedButton(
            onPressed: () {
              ref.read(favoritesRepositoryProvider).addFavoriteAddress(
                userId, 
                labelController.text, 
                addressController.text, 
                selectedIcon
              );
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
            child: const Text('AJOUTER'),
          ),
        ],
      ),
    );
  }
}
