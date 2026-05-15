import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_payment/transen_payment.dart';

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
        // Calcul des bornes incluant TOUS les points (chauffeur, passagers, destination)
        double minLat = driverPos.latitude;
        double maxLat = driverPos.latitude;
        double minLng = driverPos.longitude;
        double maxLng = driverPos.longitude;

        final allPoints = [
          driverPos,
          LatLng(dest.latitude, dest.longitude),
          ..._optimizedPickups.map((e) => LatLng(e.value['lat'], e.value['lng']))
        ];

        for (var point in allPoints) {
          if (point.latitude < minLat) minLat = point.latitude;
          if (point.latitude > maxLat) maxLat = point.latitude;
          if (point.longitude < minLng) minLng = point.longitude;
          if (point.longitude > maxLng) maxLng = point.longitude;
        }

        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          70.0, // Padding généreux
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
        builder: (_, snapshot) {
          final pool = snapshot.data ?? widget.pool;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Itinéraire Porte-à-Porte'),
              backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A1A) : Colors.black87,
              foregroundColor: Colors.white,
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: Theme.of(context).brightness == Brightness.dark 
                        ? [const Color(0xFF1A1A1A), const Color(0xFF0A0A0A)]
                        : [Colors.black87, Colors.black],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
                    boxShadow: [
                      BoxShadow(
                        color: TranSenColors.primaryGreen.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: TranSenColors.primaryGreen.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: TranSenColors.primaryGreen.withValues(alpha: 0.3), width: 1.5),
                            ),
                            child: const Icon(Icons.route_rounded, color: TranSenColors.primaryGreen, size: 28),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("ITINÉRAIRE EN COURS", 
                                  style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${pool.departure} ➔ ${pool.destination}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: -0.5
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildHeaderStat("PASSAGERS", "${pool.currentFilling}/4", Icons.people_outline),
                          _buildHeaderStat("STATUT", pool.status.toUpperCase(), Icons.info_outline),
                          _buildHeaderStat("PRIX FIXE", "10.000 F", Icons.payments_outlined),
                        ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
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
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text("LANCER LA NAVIGATION GOOGLE MAPS", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF121212) : Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5))
                      ],
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _optimizedPickups.length,
                      itemBuilder: (_, index) {
                        final passengerEntry = _optimizedPickups[index];
                        final passengerId = passengerEntry.key;
                        final passenger = passengerEntry.value;
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
                              passengerId,
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: (pool.status == 'accepted' ? TranSenColors.accentGold : Colors.black).withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        try {
                          final repo = ref.read(tripRepositoryProvider);
                          if (pool.status == 'accepted') {
                            await repo.departPool(pool.id);
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text("🚀 Trajet démarré !"),
                                    backgroundColor: Colors.green),
                              );
                            }
                          } else {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text("Finalisation du trajet..."), duration: Duration(seconds: 1)),
                              );
                            }
                            await repo.completeTrip(pool.id);
                            if (mounted) {
                              navigator.pop();
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text("✅ Trajet terminé avec succès !"),
                                    backgroundColor: Colors.green),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text("❌ Erreur: ${e.toString().replaceAll("Exception: ", "")}"),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: pool.status == 'accepted'
                            ? TranSenColors.accentGold
                            : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.black87),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        elevation: 0,
                      ),
                      child: Center(
                        child: Text(
                          pool.status == 'accepted'
                              ? "DÉMARRER LE TRAJET"
                              : "TERMINER LE TRAJET",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
  }

  Future<bool> _hasAccess() async {
    final auth = ref.read(authProvider);
    if (auth == null) return false;
    
    // 1. Vérifier l'abonnement
    final subInfo = await SubscriptionService().checkSubscription(auth.userId);
    if (subInfo.isActive) return true;
    
    // 2. Vérifier le solde (Pool prix fixe 10000F, donc 1% = 100F)
    final wallet = ref.read(walletProvider);
    const commission = 100.0; 
    
    if (wallet.balance < commission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ Rechargez votre portefeuille TransPay (${commission.toInt()}F requis) pour contacter les passagers."),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: "RECHARGER",
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                }
              },
            ),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Widget _buildHeaderStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: TranSenColors.primaryGreen, size: 18),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildStepCard(int step, String name, String passengerId, Map<String, dynamic> passenger, String info) {
    String initialPhone = passenger['phone'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text("$step", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.grey, size: 12),
                          const SizedBox(width: 4),
                          Expanded(child: Text(info, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 0.5),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionCircle(
                  icon: Icons.navigation_outlined, 
                  color: Colors.blue, 
                  onTap: () => launchUrl(Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${passenger['lat']},${passenger['lng']}&travelmode=driving"))
                ),
                _buildActionCircle(
                  icon: Icons.message_outlined, 
                  color: Colors.green, 
                  onTap: () async {
                    if (await _hasAccess()) DeviceUtils.launchWhatsApp(initialPhone);
                  }
                ),
                _buildActionCircle(
                  icon: Icons.chat_bubble_outline_rounded, 
                  color: TranSenColors.primaryGreen, 
                  onTap: () async {
                    if (await _hasAccess()) {
                      if (!mounted) return;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(tripId: widget.pool.id, otherPartyName: name, passengerId: passengerId)));
                    }
                  }
                ),
                _buildActionCircle(
                  icon: Icons.phone_enabled_outlined, 
                  color: Colors.blueAccent, 
                  onTap: () async {
                    if (await _hasAccess()) {
                      // Fetch fresh phone
                      final userDoc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(passengerId).get();
                      String phone = initialPhone;
                      if (userDoc.exists && userDoc.data()?['phone'] != null) phone = userDoc.data()!['phone'];
                      DeviceUtils.launchPhoneCall(phone);
                    }
                  }
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCircle({required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
