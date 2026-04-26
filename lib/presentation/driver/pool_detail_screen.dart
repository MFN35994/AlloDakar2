import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/transen_colors.dart';

import '../../domain/models/pool_model.dart';
import '../../domain/utils/itinerary_optimizer.dart';
import '../../data/repositories/trip_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class PoolDetailScreen extends ConsumerStatefulWidget {
  final PoolModel pool;

  const PoolDetailScreen({super.key, required this.pool});

  @override
  ConsumerState<PoolDetailScreen> createState() => _PoolDetailScreenState();
}

class _PoolDetailScreenState extends ConsumerState<PoolDetailScreen> {
  late List<MapEntry<String, dynamic>> _optimizedPickups;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isRoutePlotted = false;
  LatLng? _myPosition;

  @override
  void initState() {
    super.initState();
    // Optimization simple : Part du centre de Dakar (ou position réelle du chauffeur)
    _optimizedPickups = ItineraryOptimizer.optimizePickupOrder(
      const LatLng(14.7167, -17.4677),
      widget.pool.passengerDetails,
    );
    _buildMarkers();
    _fetchMyPositionAndRoute();
  }

  void _fetchMyPositionAndRoute() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      LatLng driverPos = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _myPosition = driverPos;
          _optimizedPickups = ItineraryOptimizer.optimizePickupOrder(
            driverPos,
            widget.pool.passengerDetails,
          );
        });
      }

      _getPolyline(driverPos);
    } catch (_) {}
  }

  void _getPolyline(LatLng driverPos) async {
    if (_isRoutePlotted || _optimizedPickups.isEmpty) return;
    _isRoutePlotted = true;

    List<PolylineWayPoint> waypoints = [];
    for (var entry in _optimizedPickups) {
      final wp = entry.value;
      if (wp['lat'] != null && wp['lng'] != null) {
        waypoints.add(PolylineWayPoint(
            location: "${wp['lat']},${wp['lng']}", stopOver: true));
      }
    }

    // Point d'arrivée final (Région de destination)
    final destCoords =
        ItineraryOptimizer.getRegionCoordinates(widget.pool.destination);
    PointLatLng dest = destCoords != null
        ? PointLatLng(destCoords.latitude, destCoords.longitude)
        : const PointLatLng(14.7167, -17.4677);

    PolylinePoints polylinePoints = PolylinePoints(apiKey: "AIzaSyBw0PKiF8FdoPE26gIP2s1e7XJCozN6rLE");
    // ignore: deprecated_member_use
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      // ignore: deprecated_member_use
      request: PolylineRequest(
        origin: PointLatLng(driverPos.latitude, driverPos.longitude),
        destination: dest,
        mode: TravelMode.driving,
        wayPoints: waypoints,
      ),
    );

    if (result.points.isNotEmpty) {
      List<LatLng> polylineCoordinates = [];
      for (var point in result.points) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }

      if (mounted) {
        setState(() {
          _polylines.add(Polyline(
            polylineId: const PolylineId("route"),
            color: TranSenColors.primaryGreen,

            width: 5,
            points: polylineCoordinates,
          ));
        });
      }

      if (_myPosition != null) {
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              driverPos.latitude < dest.latitude
                  ? driverPos.latitude
                  : dest.latitude,
              driverPos.longitude < dest.longitude
                  ? driverPos.longitude
                  : dest.longitude,
            ),
            northeast: LatLng(
              driverPos.latitude > dest.latitude
                  ? driverPos.latitude
                  : dest.latitude,
              driverPos.longitude > dest.longitude
                  ? driverPos.longitude
                  : dest.longitude,
            ),
          ),
          50.0,
        ));
      }
    }
  }

  void _buildMarkers() {
    _markers.clear();
    for (var passenger in widget.pool.passengerDetails.values) {
      if (passenger['lat'] != null && passenger['lng'] != null) {
        String pName = passenger['name'] ?? 'Passager';
        if (passenger['firstName'] != null && passenger['lastName'] != null) {
          pName = "${passenger['firstName']} ${passenger['lastName']}";
        }
        _markers.add(Marker(
          markerId: MarkerId(passenger['phone'] ?? pName),
          position: LatLng(passenger['lat'], passenger['lng']),
          infoWindow: InfoWindow(title: pName, snippet: passenger['phone']),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),

        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PoolModel?>(
        stream: ref.watch(tripRepositoryProvider).watchPool(widget.pool.id),
        builder: (context, snapshot) {
          final pool = snapshot.data ?? widget.pool;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Itinéraire Porte-à-Porte'),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            ),
            body: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: TranSenColors.primaryGreen.withValues(alpha: 0.1),

                  child: Row(
                    children: [
                      const Icon(Icons.route, color: TranSenColors.primaryGreen),

                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${pool.departure} ➔ ${pool.destination}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              "Status: ${pool.status.toUpperCase()} (${pool.currentFilling}/4 passagers)",
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(
                        target: LatLng(14.7167, -17.4677), zoom: 14),
                    onMapCreated: (GoogleMapController controller) async {
                      _mapController = controller;
                      if (_myPosition != null && !_isRoutePlotted) {
                        _mapController?.animateCamera(
                          CameraUpdate.newLatLng(_myPosition!),
                        );
                      }
                    },
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    trafficEnabled: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final origin = "${_myPosition?.latitude},${_myPosition?.longitude}";
                        final destination = pool.destination;
                        final waypoints = _optimizedPickups
                            .map((e) => "${e.value['lat']},${e.value['lng']}")
                            .join('|');
                        final url = "https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=$waypoints&travelmode=driving";
                        launchUrl(Uri.parse(url));
                      },
                      icon: const Icon(Icons.navigation),
                      label: const Text("LANCER LA NAVIGATION GOOGLE MAPS", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5))
                      ],
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _optimizedPickups.length,
                      itemBuilder: (context, index) {
                        final passenger = _optimizedPickups[index].value;
                        final isLast = index == _optimizedPickups.length - 1;

                        String pName = passenger['name'] ?? 'Passager';
                        if (passenger['firstName'] != null &&
                            passenger['lastName'] != null) {
                          pName =
                              "${passenger['firstName']} ${passenger['lastName']}";
                        }

                        return Column(
                          children: [
                            _buildStepCard(
                              index + 1,
                              pName,
                              passenger,
                              "Récupération: ${pool.departure}",
                            ),
                            if (!isLast)
                              const Icon(Icons.arrow_downward,
                                  color: Colors.grey, size: 20),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ElevatedButton(
                    onPressed: () async {
                      final repo = ref.read(tripRepositoryProvider);
                      if (pool.status == 'accepted') {
                        await repo.departPool(pool.id);
                        if (mounted) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Trajet démarré !"),
                                backgroundColor: Colors.green),
                          );
                        }
                      } else {
                        await repo.completeTrip(pool.id);
                        if (mounted) {
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pool.status == 'accepted'
                          ? TranSenColors.accentGold

                          : Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Center(
                      child: Text(
                        pool.status == 'accepted'
                            ? "DÉMARRER LE TRAJET"
                            : "TERMINER LE TRAJET",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
  }

  Widget _buildStepCard(int step, String name, Map<String, dynamic> passenger, String info) {
    final phone = passenger['phone'] ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TranSenColors.primaryGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.black87,
          child: Text("$step",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(info, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.navigation, color: Colors.blue),
              onPressed: () => launchUrl(Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${passenger['lat']},${passenger['lng']}&travelmode=driving")),
            ),
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              onPressed: () => launchUrl(Uri.parse("tel:$phone")),
            ),
          ],
        ),
      ),
    );
  }
}
