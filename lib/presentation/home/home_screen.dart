import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:transen_core/transen_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:transen_maps/transen_maps.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_trips/transen_trips.dart' as providers;
import 'package:transen/presentation/widgets/profile_drawer.dart';

final activeDriversStreamProvider = StreamProvider<Set<Marker>>((ref) {
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
      .collection('active_drivers')
      .snapshots()
      .asyncMap((snapshot) async {
    final markers = <Marker>{};
    final icon = await MapMarkerUtils.getCarIcon();
    
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final driverId = doc.id;
      if (data['status'] != 'online') continue;
      
      if (data['lastUpdated'] != null) {
        final lastUpdated = (data['lastUpdated'] as Timestamp).toDate();
        if (DateTime.now().difference(lastUpdated).inMinutes > 10) continue;
      }
      
      final dep = data['departure'];
      final dest = data['destination'];
      final note = data['note'];
      String snippet = "Chauffeur actif";
      if (dep != null || dest != null) {
        snippet = "Trajet : ${dep ?? '?'} ➔ ${dest ?? '?'}";
        if (note != null && note.toString().isNotEmpty) {
          snippet += " | $note";
        }
      }
      
      markers.add(Marker(
        markerId: MarkerId(driverId),
        position: LatLng(data['lat'], data['lng']),
        infoWindow: InfoWindow(
          title: data['driverName'] ?? 'Chauffeur TranSen',
          snippet: snippet,
        ),
        icon: icon,
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
              markers: driverMarkers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(40),
              topRight: Radius.circular(40),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.45,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light 
                      ? Colors.white.withValues(alpha: 0.4) 
                      : Colors.white.withValues(alpha: 0.05)
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Que voulez-vous faire ?', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  
                  Consumer(builder: (context, ref, child) {
                    final activePoolAsync = ref.watch(providers.activePoolProvider);
                    final activeTripAsync = ref.watch(providers.activeTripProvider);
                    return Column(
                      children: [
                        activePoolAsync.when(
                          data: (pool) => pool == null ? const SizedBox.shrink() : _buildActiveTripCard(context, pool, isYobante: false),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        activeTripAsync.when(
                          data: (trip) => trip == null ? const SizedBox.shrink() : _buildActiveTripCard(context, trip, isYobante: true),
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
                        onTap: () => OrderSheet.show(context),
                      ),
                      _buildActionCard(
                        context,
                        title: 'Yobanté',
                        icon: Icons.inventory_2,
                        color: Colors.blue,
                        onTap: () => YobanteSheet.show(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            Position pos = await Geolocator.getCurrentPosition();
            _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
          } catch (_) {}
        },
        backgroundColor: TranSenColors.primaryGreen,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }

  Widget _buildActiveTripCard(BuildContext context, TripModel trip, {required bool isYobante}) {
    final color = isYobante ? Colors.blue : TranSenColors.primaryGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color, child: Icon(isYobante ? Icons.inventory_2 : Icons.directions_car, color: Colors.white)),
        title: Text(isYobante ? "Livraison en cours..." : "Course en cours...", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text("${trip.departure} ➔ ${trip.destination}"),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: color),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripTrackingScreen(tripId: trip.id))),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: () async {
        await HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light ? Colors.white : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15), 
              blurRadius: 15, 
              offset: const Offset(0, 8)
            )
          ],
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1.5,
          ),
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
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
