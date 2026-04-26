import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../core/theme/transen_colors.dart';
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
import '../widgets/driver_reviews_sheet.dart';
import '../widgets/skeleton_loader.dart';

final activeDriversStreamProvider = StreamProvider<Set<Marker>>((ref) {
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
      .collection('active_drivers')
      .snapshots()
      .asyncMap((snapshot) async {
    final markers = <Marker>{};
    
    // Créer une icône voiture transparente avec Canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 40.0;
    final paint = Paint()..color = TranSenColors.primaryGreen;
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
          title: data['driverName'] ?? 'Chauffeur TranSen',
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
        title: const Text('TranSen'),
        backgroundColor: Theme.of(context).colorScheme.primary,
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
                  
                  // CARTES ACTIVES (Course et Yobanté indépendantes)
                  Consumer(builder: (context, ref, child) {
                    final activePoolAsync = ref.watch(providers.activePoolProvider);
                    final activeTripAsync = ref.watch(providers.activeTripProvider);

                    return Column(
                      children: [
                        activePoolAsync.when(
                          data: (pool) {
                            if (pool == null) return const SizedBox.shrink();
                            return _buildActiveTripCard(context, pool, isYobante: false);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        activeTripAsync.when(
                          data: (trip) {
                            if (trip == null) return const SizedBox.shrink();
                            return _buildActiveTripCard(context, trip, isYobante: true);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
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
                        color: TranSenColors.primaryGreen,
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
                                  border: Border.all(color: TranSenColors.primaryGreen.withValues(alpha: 0.3), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(color: TranSenColors.primaryGreen.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.auto_awesome, color: TranSenColors.primaryGreen, size: 24),
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
                                            style: const TextStyle(fontSize: 11, color: TranSenColors.primaryGreen, fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  DriverReviewsSheet.show(
                                                    context, 
                                                    m.markerId.value, 
                                                    m.infoWindow.title ?? 'Chauffeur'
                                                  );
                                                },
                                                child: Consumer(builder: (context, ref, child) {
                                                  final ratingAsync = ref.watch(providers.driverRatingProvider(m.markerId.value));
                                                  final countAsync = ref.watch(providers.driverRatingCountProvider(m.markerId.value));
                                                  
                                                  return Row(
                                                    children: [
                                                      const Icon(Icons.star, color: Colors.amber, size: 14),
                                                      const SizedBox(width: 2),
                                                      Text(
                                                        ratingAsync.value?.toStringAsFixed(1) ?? '0.0',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        "(${countAsync.value ?? 0})",
                                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                      ),
                                                    ],
                                                  );
                                                }),
                                              ),
                                              const Spacer(),
                                              const Text(
                                                "Réserver",
                                                style: TextStyle(fontSize: 9, color: Colors.grey, decoration: TextDecoration.underline),
                                              ),
                                            ],
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
                      loading: () => ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 3,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(right: 15),
                            child: const SkeletonLoader(width: 200, height: 110, borderRadius: 20),
                          );
                        },
                      ),
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
        backgroundColor: TranSenColors.primaryGreen,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }

  Widget _buildActiveTripCard(BuildContext context, TripModel trip, {required bool isYobante}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isYobante 
            ? Colors.blue.withValues(alpha: 0.1) 
            : TranSenColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isYobante ? Colors.blue : TranSenColors.primaryGreen, 
            width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: isYobante ? Colors.blue : TranSenColors.primaryGreen,
          child: Icon(isYobante ? Icons.inventory_2 : Icons.directions_car, color: Colors.white),
        ),
        title: Text(
          isYobante ? "Livraison en cours..." : "Course en cours...",
          style: TextStyle(
              fontWeight: FontWeight.bold, 
              color: isYobante ? Colors.blue : TranSenColors.primaryGreen),
        ),
        subtitle: Text("${trip.departure} ➔ ${trip.destination}"),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, 
            color: isYobante ? Colors.blue : TranSenColors.primaryGreen),
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
