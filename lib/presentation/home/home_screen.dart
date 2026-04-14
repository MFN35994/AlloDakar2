import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import '../widgets/order_sheet.dart';
import '../widgets/yobante_sheet.dart';
import '../../domain/providers/trip_providers.dart' as providers;
import '../../domain/models/trip_model.dart';
import '../widgets/profile_drawer.dart';
import './trip_tracking_screen.dart';

final activeDriversStreamProvider = StreamProvider<Set<Marker>>((ref) {
  return FirebaseFirestore.instance
      .collection('active_drivers')
      .snapshots()
      .asyncMap((snapshot) async {
    final markers = <Marker>{};
    
    // Créer une icône voiture transparente avec Canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 40.0;
    final paint = Paint()..color = Colors.orange;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(6, 14, 28, 16), const Radius.circular(5)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(11, 6, 18, 11), const Radius.circular(4)), paint);
    canvas.drawCircle(const Offset(11, 30), 4, Paint()..color = Colors.black87);
    canvas.drawCircle(const Offset(29, 30), 4, Paint()..color = Colors.black87);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final carIcon = BitmapDescriptor.bytes(byteData!.buffer.asUint8List());

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final driverId = doc.id;

      // 1. Filtrer par statut
      if (data['status'] != 'online') continue;

      // 2. Filtrer par fraîcheur (stale data) - Max 10 minutes
      if (data['lastUpdated'] != null) {
        final lastUpdated = (data['lastUpdated'] as Timestamp).toDate();
        if (DateTime.now().difference(lastUpdated).inMinutes > 10) continue;
      }
      
      // Récupérer la route directement du document (optimisé)
      final dep = data['departure'];
      final dest = data['destination'];
      String snippet = "Chauffeur actif";
      if (dep != null && dest != null) {
        snippet = "Trajet : $dep ➔ $dest";
      }

      markers.add(Marker(
        markerId: MarkerId(driverId),
        position: LatLng(data['lat'], data['lng']),
        infoWindow: InfoWindow(
          title: data['driverName'] ?? 'Chauffeur Allô Dakar',
          snippet: snippet,
        ),
        icon: carIcon,
        rotation: 0,
      ));
    }
    return markers;
  });
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(14.7167, -17.4677),
    zoom: 13.0,
  );

  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final driverMarkers = ref.watch(activeDriversStreamProvider).value ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Allô Dakar'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      drawer: const ProfileDrawer(),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              onMapCreated: (GoogleMapController controller) async {
                _mapController = controller;
                try {
                  Position position = await Geolocator.getCurrentPosition();
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
                  );
                } catch (_) {}
              },
              markers: {
                const Marker(
                  markerId: MarkerId('current_pos'),
                  position: LatLng(14.7167, -17.4677),
                  infoWindow: InfoWindow(title: 'Votre position'),
                ),
                ...driverMarkers,
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              zoomControlsEnabled: false,
            ),
          ),
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.light 
                      ? Colors.black.withValues(alpha: 0.08) 
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Que voulez-vous faire ?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // CARTE COURSE ACTIVE
                  Consumer(builder: (context, ref, child) {
                    final activeTripAsync = ref.watch(providers.activeTripProvider);
                    return activeTripAsync.when(
                      data: (trip) {
                        if (trip == null) return const SizedBox.shrink();
                        return _buildActiveTripCard(context, trip);
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  }),

                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      _buildActionCard(
                        context,
                        title: 'Course',
                        icon: Icons.directions_car,
                        color: Colors.orange,
                        onTap: () {
                          OrderSheet.show(context);
                        },
                      ),
                      _buildActionCard(
                        context,
                        title: 'Yobante (colis)',
                        icon: Icons.inventory_2,
                        color: Colors.blue,
                        onTap: () {
                          YobanteSheet.show(context);
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 30),
                  const Text(
                    'Trajets Chauffeurs Disponibles',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 110,
                    child: ref.watch(activeDriversStreamProvider).when(
                      data: (markers) {
                        // Filtrer pour ne garder que ceux qui ont un trajet publié (contenant la flèche)
                        final announcedDrivers = markers.where((m) => m.infoWindow.snippet != null && m.infoWindow.snippet!.contains('➔')).toList();
                        
                        if (announcedDrivers.isEmpty) {
                          return Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                            ),
                            child: const Text(
                              "Aucune annonce de trajet pour le moment.",
                              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                            ),
                          );
                        }
                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: announcedDrivers.length,
                          itemBuilder: (context, index) {
                            final m = announcedDrivers[index];
                            final snippet = m.infoWindow.snippet ?? '';
                            
                            // Extraire départ/arrivée du snippet "Trajet : Dakar ➔ Thiès"
                            String? departure;
                            String? destination;
                            if (snippet.contains('➔')) {
                              final parts = snippet.replaceFirst("Trajet : ", "").split('➔');
                              if (parts.length == 2) {
                                departure = parts[0].trim();
                                destination = parts[1].trim();
                              }
                            }

                            return GestureDetector(
                              onTap: () {
                                OrderSheet.show(
                                  context,
                                  departure: departure,
                                  destination: destination,
                                  driverId: m.markerId.value,
                                );
                              },
                              child: Container(
                                width: 200,
                                margin: const EdgeInsets.only(right: 15),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey.shade900,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: Colors.orange.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.auto_awesome, color: Colors.orange, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            m.infoWindow.title ?? 'Chauffeur',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            snippet.replaceFirst("Trajet : ", ""),
                                            style: const TextStyle(fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            "Réserver",
                                            style: TextStyle(fontSize: 9, color: Colors.grey, decoration: TextDecoration.underline),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(_initialPosition),
          );
        },
        backgroundColor: Colors.orange,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }

  Widget _buildActiveTripCard(BuildContext context, TripModel trip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange, width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.directions_car, color: Colors.white),
        ),
        title: const Text(
          "Course en cours...",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
        ),
        subtitle: Text("${trip.departure} ➔ ${trip.destination}"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.orange),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TripTrackingScreen(tripId: trip.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 15,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
