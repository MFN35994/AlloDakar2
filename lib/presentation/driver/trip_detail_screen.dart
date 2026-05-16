import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final TripModel trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _myPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isRoutePlotted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndGetLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndGetLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _myPosition = LatLng(pos.latitude, pos.longitude);
        _buildMarkers();
      });
      _getPolyline(LatLng(pos.latitude, pos.longitude));
    }

    _positionStream = Geolocator.getPositionStream().listen((pos) {
      if (mounted) {
        setState(() {
          _myPosition = LatLng(pos.latitude, pos.longitude);
          _buildMarkers();
        });
      }
    });
  }

  void _getPolyline(LatLng driverPos) async {
    if (_isRoutePlotted) return;
    
    LatLng? clientPos;
    // Tenter de récupérer la position du client depuis passengerDetails (si VTC moderne)
    if (widget.trip.passengerDetails != null && widget.trip.passengerDetails!.isNotEmpty) {
      final first = widget.trip.passengerDetails!.values.first;
      if (first['lat'] != null && first['lng'] != null) {
        clientPos = LatLng(first['lat'], first['lng']);
      }
    }
    
    // Fallback sur les coordonnées de la région de départ
    clientPos ??= ItineraryOptimizer.getRegionCoordinates(widget.trip.departure) ?? const LatLng(14.7167, -17.4677);
    
    // Destination
    final destPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.destination) ?? const LatLng(14.7167, -17.4677);

    PolylinePoints polylinePoints = PolylinePoints(apiKey: "AIzaSyBw0PKiF8FdoPE26gIP2s1e7XJCozN6rLE");
    
    // ignore: deprecated_member_use
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      // ignore: deprecated_member_use
      request: PolylineRequest(
        origin: PointLatLng(driverPos.latitude, driverPos.longitude),
        destination: PointLatLng(destPos.latitude, destPos.longitude),
        mode: TravelMode.driving,
        wayPoints: [
          PolylineWayPoint(location: "${clientPos.latitude},${clientPos.longitude}", stopOver: true)
        ],
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
            width: 6,
            points: polylineCoordinates,
          ));
          _isRoutePlotted = true;
        });
        
        _fitMap(driverPos, clientPos, destPos);
      }
    }
  }

  void _fitMap(LatLng p1, LatLng p2, LatLng p3) {
    double minLat = [p1.latitude, p2.latitude, p3.latitude].reduce((a, b) => a < b ? a : b);
    double maxLat = [p1.latitude, p2.latitude, p3.latitude].reduce((a, b) => a > b ? a : b);
    double minLng = [p1.longitude, p2.longitude, p3.longitude].reduce((a, b) => a < b ? a : b);
    double maxLng = [p1.longitude, p2.longitude, p3.longitude].reduce((a, b) => a > b ? a : b);

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      70,
    ));
  }

  void _buildMarkers() {
    _markers.clear();
    if (_myPosition != null) {
      _markers.add(Marker(
        markerId: const MarkerId("driver"),
        position: _myPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: "Ma Position"),
      ));
    }

    // Client Marker
    LatLng? clientPos;
    if (widget.trip.passengerDetails != null && widget.trip.passengerDetails!.isNotEmpty) {
      final first = widget.trip.passengerDetails!.values.first;
      if (first['lat'] != null && first['lng'] != null) {
        clientPos = LatLng(first['lat'], first['lng']);
      }
    }
    clientPos ??= ItineraryOptimizer.getRegionCoordinates(widget.trip.departure);
    
    if (clientPos != null) {
      _markers.add(Marker(
        markerId: const MarkerId("client"),
        position: clientPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: "Client: ${widget.trip.clientName ?? 'Ramassage'}"),
      ));
    }

    // Destination Marker
    final destPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.destination);
    if (destPos != null) {
      _markers.add(Marker(
        markerId: const MarkerId("destination"),
        position: destPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Destination Finale"),
      ));
    }
  }

  Future<bool> _hasAccess() async {
    final auth = ref.read(authProvider);
    if (auth == null) return false;
    
    final subInfo = await SubscriptionService().checkSubscription(auth.userId);
    if (subInfo.isActive) return true;
    
    final wallet = ref.read(walletProvider);
    final commission = widget.trip.price * 0.01;
    
    if (wallet.balance < commission) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("⚠️ Rechargez votre portefeuille TransPay (${commission.toInt()}F requis) pour contacter le client."),
          backgroundColor: Colors.orange.shade900,
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
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Détails de la course', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Carte Interactive
          Expanded(
            flex: 6,
            child: Container(
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _myPosition ?? const LatLng(14.7167, -17.4677),
                    zoom: 13,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
              ),
            ),
          ),
          
          // Détails Panel
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Client Info
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.black, Color(0xFF2D2D2D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: TranSenColors.primaryGreen.withValues(alpha: 0.1),
                          child: const Icon(Icons.person, color: TranSenColors.primaryGreen, size: 30),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.trip.clientName ?? 'Client TranSen',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                widget.trip.type.toUpperCase(),
                                style: const TextStyle(color: TranSenColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                            ],
                          ),
                        ),
                        Text("${widget.trip.price.toInt()} F", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Trajet Info
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)]
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.my_location_rounded, "Départ", widget.trip.departure, Colors.blue),
                        const SizedBox(height: 15),
                        _buildInfoRow(Icons.location_on_rounded, "Arrivée", widget.trip.destination, Colors.redAccent),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  StreamBuilder<DocumentSnapshot>(
                    stream: widget.trip.clientId != null ? FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(widget.trip.clientId).snapshots() : null,
                    builder: (context, snapshot) {
                      String phoneToCall = widget.trip.clientPhone ?? '770000000';
                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        if (data['phone'] != null && (data['phone'] as String).isNotEmpty) phoneToCall = data['phone'];
                      }
                      return Column(
                        children: [
                          Row(
                            children: [
                              _buildActionCircle(
                                icon: Icons.phone_enabled_rounded, color: Colors.blue, label: "Appeler",
                                onTap: () async { if (await _hasAccess()) DeviceUtils.launchPhoneCall(phoneToCall); }
                              ),
                              const SizedBox(width: 10),
                              _buildActionCircle(
                                icon: Icons.chat_bubble_rounded, color: TranSenColors.primaryGreen, label: "Chat",
                                onTap: () async {
                                  if (await _hasAccess()) {
                                    if (!context.mounted) return;
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(tripId: widget.trip.id, otherPartyName: widget.trip.clientName ?? 'Client')));
                                  }
                                }
                              ),
                              const SizedBox(width: 10),
                              _buildActionCircle(
                                icon: Icons.message_rounded, color: Colors.green, label: "WhatsApp",
                                onTap: () async { if (await _hasAccess()) DeviceUtils.launchWhatsApp(phoneToCall); }
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (widget.trip.status == 'pending' ? TranSenColors.primaryGreen : Colors.black).withValues(alpha: 0.3),
                                  blurRadius: 10, offset: const Offset(0, 5),
                                )
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () async {
                                 if (widget.trip.status == 'pending') {
                                   final auth = ref.read(authProvider);
                                   if (auth != null) {
                                     await ref.read(tripRepositoryProvider).acceptTrip(widget.trip.id, auth.userId);
                                     if (context.mounted) Navigator.pop(context);
                                   }
                                 } else if (widget.trip.status == 'accepted') {
                                   // Démarrer la course
                                   try {
                                     await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen')
                                         .collection('trips')
                                         .doc(widget.trip.id)
                                         .update({'status': 'ongoing'});

                                     // Lancer la navigation Mapbox
                                     Position? position;
                                     try {
                                       position = await Geolocator.getCurrentPosition(
                                         locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 5)),
                                       );
                                     } catch (e) {
                                       debugPrint("GPS Error: $e");
                                     }

                                     var wayPoints = <WayPoint>[];
                                     if (position != null) {
                                       wayPoints.add(WayPoint(name: "Ma Position", latitude: position.latitude, longitude: position.longitude));
                                     }
                                     
                                     final depPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.departure) ?? const LatLng(14.7167, -17.4677);
                                     final destPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.destination) ?? const LatLng(14.7167, -17.4677);

                                     wayPoints.add(WayPoint(name: "Point de départ", latitude: depPos.latitude, longitude: depPos.longitude));
                                     wayPoints.add(WayPoint(name: "Destination", latitude: destPos.latitude, longitude: destPos.longitude));

                                     final directions = MapBoxNavigation.instance;
                                     await directions.startNavigation(
                                       wayPoints: wayPoints,
                                       options: MapBoxOptions(
                                         initialLatitude: position?.latitude ?? depPos.latitude,
                                         initialLongitude: position?.longitude ?? depPos.longitude,
                                         zoom: 15.0,
                                         voiceInstructionsEnabled: true,
                                         mode: MapBoxNavigationMode.drivingWithTraffic,
                                       ),
                                     );
                                   } catch (navErr) {
                                     debugPrint("Erreur Navigation Mapbox: $navErr");
                                   }
                                 } else {
                                  try {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vérification GPS..."), duration: Duration(seconds: 1)));
                                    
                                    Position? position;
                                    try {
                                      position = await Geolocator.getCurrentPosition(
                                        locationSettings: const LocationSettings(
                                          accuracy: LocationAccuracy.high,
                                          timeLimit: Duration(seconds: 5),
                                        ),
                                      );
                                    } catch (geoErr) {
                                      debugPrint("GPS Error: $geoErr");
                                    }

                                    await ref.read(tripRepositoryProvider).completeTrip(
                                      widget.trip.id,
                                      currentLat: position?.latitude,
                                      currentLng: position?.longitude,
                                    );
                                    
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Course terminée !"), backgroundColor: Colors.green));
                                    }
                                  } catch (e) {
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.trip.status == 'pending'
                                    ? TranSenColors.primaryGreen
                                    : widget.trip.status == 'accepted'
                                        ? TranSenColors.accentGold
                                        : Colors.black,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 0,
                              ),
                              child: Text(
                                widget.trip.status == 'pending'
                                    ? "ACCEPTER LA COURSE"
                                    : widget.trip.status == 'accepted'
                                        ? "DÉMARRER LA COURSE"
                                        : "TERMINER LA COURSE",
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCircle({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 0.5)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            ],
          ),
        ),
      ],
    );
  }
}
