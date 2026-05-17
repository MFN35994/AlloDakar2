import 'package:flutter/material.dart';
import 'package:transen_core/transen_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_payment/transen_payment.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'dart:async';
import 'package:flutter_mapbox_navigation_plus/flutter_mapbox_navigation_plus.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

class TripDetailScreen extends ConsumerStatefulWidget {
  final TripModel trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  MapboxMap? _mapController;
  PointAnnotationManager? _annotationManager;
  LatLng? _myPosition;
  StreamSubscription<geo.Position>? _positionStream;
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
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }

    final pos = await geo.Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _myPosition = LatLng(pos.latitude, pos.longitude);
        _buildMarkers();
      });
      _getPolyline(LatLng(pos.latitude, pos.longitude));
    }

    _positionStream = geo.Geolocator.getPositionStream().listen((pos) {
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
    
    final List<String> clientCoords = [];
    LatLng? firstClientPos;
    
    if (widget.trip.passengerDetails != null && widget.trip.passengerDetails!.isNotEmpty) {
      for (var passenger in widget.trip.passengerDetails!.values) {
        if (passenger['lat'] != null && passenger['lng'] != null) {
          clientCoords.add("${passenger['lng']},${passenger['lat']}");
          firstClientPos ??= LatLng(passenger['lat'], passenger['lng']);
        }
      }
    }
    
    if (clientCoords.isEmpty) {
      final fallbackPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.departure) ?? const LatLng(14.7167, -17.4677);
      clientCoords.add("${fallbackPos.longitude},${fallbackPos.latitude}");
      firstClientPos = fallbackPos;
    }
    
    final destPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.destination) ?? const LatLng(14.7167, -17.4677);

    try {
      final dio = Dio();
      const String mapboxToken = "pk.eyJ1IjoidHJhbnNlbiIsImEiOiJjbXA4Nm5menUwM205MnNwOGZmb3N3ZTM4In0.SMFaXkbJJi5bM6Bk3_p8ng";
      
      final List<String> allCoords = [];
      allCoords.add("${driverPos.longitude},${driverPos.latitude}");
      allCoords.addAll(clientCoords);
      allCoords.add("${destPos.longitude},${destPos.latitude}");
      
      final url = "https://api.mapbox.com/optimized-trips/v1/mapbox/driving/${allCoords.join(';')}?source=first&destination=last&overview=full&geometries=geojson&access_token=$mapboxToken";
      
      final response = await dio.get(url);
      
      if (response.statusCode == 200) {
        final data = response.data;
        final trips = data['trips'] as List;
        if (trips.isNotEmpty) {
          final trip = trips[0];
          final geometry = trip['geometry'];
          
          if (_mapController != null) {
            final source = GeoJsonSource(id: "route-source", data: jsonEncode(geometry));
            await _mapController!.style.addSource(source);
            
            final layer = LineLayer(
              id: "route-layer",
              sourceId: "route-source",
              lineColor: TranSenColors.primaryGreen.toARGB32(),
              lineWidth: 6.0,
            );
            await _mapController!.style.addLayer(layer);
            
            if (mounted) {
              setState(() {
                _isRoutePlotted = true;
              });
            }
            _fitMap(driverPos, firstClientPos!, destPos);
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur Optimization API: $e");
    }

  }

  void _fitMap(LatLng p1, LatLng p2, LatLng p3) {
    double minLat = [p1.latitude, p2.latitude, p3.latitude].reduce((a, b) => a < b ? a : b);
    double maxLat = [p1.latitude, p2.latitude, p3.latitude].reduce((a, b) => a > b ? a : b);
    double minLng = [p1.longitude, p2.longitude, p3.longitude].reduce((a, b) => a < b ? a : b);
    double maxLng = [p1.longitude, p2.longitude, p3.longitude].reduce((a, b) => a > b ? a : b);

    double centerLat = (minLat + maxLat) / 2;
    double centerLng = (minLng + maxLng) / 2;

    _mapController?.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(centerLng, centerLat)),
        zoom: 12.0,
      ),
    );
  }

  void _buildMarkers() async {
    if (_annotationManager != null) {
      _annotationManager!.deleteAll();
      
      if (_myPosition != null) {
        _annotationManager!.create(PointAnnotationOptions(
          geometry: Point(coordinates: Position(_myPosition!.longitude, _myPosition!.latitude)),
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
        _annotationManager!.create(PointAnnotationOptions(
          geometry: Point(coordinates: Position(clientPos.longitude, clientPos.latitude)),
        ));
      }

      // Destination Marker
      final destPos = ItineraryOptimizer.getRegionCoordinates(widget.trip.destination);
      if (destPos != null) {
        _annotationManager!.create(PointAnnotationOptions(
          geometry: Point(coordinates: Position(destPos.longitude, destPos.latitude)),
        ));
      }
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
                child: MapWidget(
                  viewport: CameraViewportState(
                    center: Point(coordinates: Position(-17.4677, 14.7167)),
                    zoom: 13.0,
                  ),
                  onMapCreated: (MapboxMap mapboxMap) async {
                    _mapController = mapboxMap;
                    _annotationManager = await mapboxMap.annotations.createPointAnnotationManager();
                    if (_myPosition != null) {
                      _mapController?.setCamera(
                        CameraOptions(
                          center: Point(coordinates: Position(_myPosition!.longitude, _myPosition!.latitude)),
                          zoom: 13.0,
                        ),
                      );
                    }
                  },
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
                                     geo.Position? position;
                                     try {
                                       position = await geo.Geolocator.getCurrentPosition(
                                         locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high, timeLimit: Duration(seconds: 5)),
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
                                    
                                    geo.Position? position;
                                    try {
                                      position = await geo.Geolocator.getCurrentPosition(
                                        locationSettings: const geo.LocationSettings(
                                          accuracy: geo.LocationAccuracy.high,
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
