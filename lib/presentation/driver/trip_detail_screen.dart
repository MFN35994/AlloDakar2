import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TripDetailScreen extends ConsumerWidget {
  final TripModel trip;

  const TripDetailScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Détails de la course'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte Info Client
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.person, color: Colors.white, size: 35),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    trip.clientName ?? 'Client Allô Dakar',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    trip.type,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // Détails du trajet
            const Text("INFORMATIONS TRAJET", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 15),
            _buildInfoRow(Icons.my_location, "Départ", trip.departure, Colors.blue),
            const Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Icon(Icons.more_vert, size: 16, color: Colors.grey)),
            _buildInfoRow(Icons.location_on, "Destination", trip.destination, Colors.red),
            
            const Divider(height: 40),

            // Spécificités
            if (trip.seats != null)
              _buildSimpleRow(Icons.groups, "Nombre de places", "${trip.seats}"),
            if (trip.scheduledDate != null)
              _buildSimpleRow(Icons.calendar_today, "Date prévue", trip.scheduledDate!),
            if (trip.baggageDescription != null && trip.baggageDescription!.isNotEmpty)
              _buildSimpleRow(Icons.inventory, "Bagages", trip.baggageDescription!),
            
            _buildSimpleRow(Icons.payments, "Prix à encaisser", "${trip.price.toInt()} FCFA"),

            const SizedBox(height: 40),

            // Boutons d'action
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => launchUrl(Uri.parse("tel:${trip.clientPhone ?? '770000000'}")),
                    icon: const Icon(Icons.phone),
                    label: const Text("APPELER"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: trip.status == 'pending'
                    ? ElevatedButton.icon(
                        onPressed: () async {
                          final auth = ref.read(authProvider);
                          if (auth != null) {
                            await ref.read(tripRepositoryProvider).acceptTrip(trip.id, auth.userId);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text("ACCEPTER"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () async {
                          await ref.read(tripRepositoryProvider).completeTrip(trip.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check),
                        label: const Text("TERMINER"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildSimpleRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(width: 15),
          Text("$label : ", style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
