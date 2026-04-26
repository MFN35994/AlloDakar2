import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../core/theme/transen_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/providers/trip_providers.dart' as providers;
import '../../domain/providers/auth_provider.dart';
import '../../domain/models/trip_model.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/driver_reviews_sheet.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'dart:ui' as ui;

class TripTrackingScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripTrackingScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends ConsumerState<TripTrackingScreen> {
  gmaps.GoogleMapController? _mapController;
  final Set<gmaps.Marker> _markers = {};
  final Set<gmaps.Polyline> _polylines = {};
  gmaps.BitmapDescriptor? _carIcon;
  gmaps.LatLng? _myPosition;
  bool _isRoutePlotted = false;

  /// Crée un icône voiture 48×48 avec fond transparent
  Future<gmaps.BitmapDescriptor> _buildCarMarker() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 48.0;

    final paint = Paint()..color = TranSenColors.primaryGreen;
    // Corps voiture
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 16, 32, 20), const Radius.circular(6)),
      paint,
    );
    // Toit
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 8, 20, 12), const Radius.circular(4)),
      paint,
    );
    // Roue avant
    canvas.drawCircle(const Offset(14, 36), 5, Paint()..color = Colors.black87);
    // Roue arriere
    canvas.drawCircle(const Offset(34, 36), 5, Paint()..color = Colors.black87);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  @override
  void initState() {
    super.initState();
    _loadMarkerIcon();
    _fetchMyPosition();
  }

  void _fetchMyPosition() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _myPosition = gmaps.LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (_) {}
  }

  void _getPolyline(gmaps.LatLng driverPos, gmaps.LatLng clientPos) async {
    if (_isRoutePlotted) return;
    _isRoutePlotted = true;

    try {
      PolylinePoints polylinePoints = PolylinePoints(apiKey: "AIzaSyBw0PKiF8FdoPE26gIP2s1e7XJCozN6rLE");
      // ignore: deprecated_member_use
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        // ignore: deprecated_member_use
        request: PolylineRequest(
          origin: PointLatLng(driverPos.latitude, driverPos.longitude),
          destination: PointLatLng(clientPos.latitude, clientPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      debugPrint("[Polyline] status=${result.status} points=${result.points.length} errorMsg=${result.errorMessage}");

      if (result.points.isNotEmpty) {
        List<gmaps.LatLng> polylineCoordinates = result.points
            .map((p) => gmaps.LatLng(p.latitude, p.longitude))
            .toList();
        
        if (mounted) {
          setState(() {
            _polylines.add(gmaps.Polyline(
              polylineId: const gmaps.PolylineId("route"),
              color: Colors.blue,
              width: 6,
              points: polylineCoordinates,
              startCap: gmaps.Cap.roundCap,
              endCap: gmaps.Cap.roundCap,
            ));
          });
        }
      } else {
        // Fallback: ligne droite si l'API ne répond pas
        _drawStraightLine(driverPos, clientPos);
      }
    } catch (e) {
      debugPrint("[Polyline] Erreur: $e");
      _drawStraightLine(driverPos, clientPos);
    }
  }

  void _drawStraightLine(gmaps.LatLng from, gmaps.LatLng to) {
    if (mounted) {
      setState(() {
        _polylines.add(gmaps.Polyline(
          polylineId: const gmaps.PolylineId("route"),
          color: Colors.blue.withValues(alpha: 0.7),
          width: 4,
          points: [from, to],
          patterns: [gmaps.PatternItem.dash(20), gmaps.PatternItem.gap(10)],
        ));
      });
    }
  }

  void _loadMarkerIcon() async {
    _carIcon = await _buildCarMarker();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tripRepo = ref.watch(tripRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de ma demande'),
        backgroundColor: TranSenColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<TripModel?>(
        stream: tripRepo.watchTrip(widget.tripId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen));
          }
          final trip = snapshot.data;
          if (trip == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.search_off, size: 60, color: Colors.grey),
                   const SizedBox(height: 10),
                   const Text("Demande introuvable.", style: TextStyle(fontWeight: FontWeight.bold)),
                   TextButton(onPressed: () => Navigator.pop(context), child: const Text("RETOUR")),
                ],
              ),
            );
          }

          if (trip.status == 'pending' || trip.status == 'open' || trip.status == 'full') {
            return _buildSearchingView(trip);
          }

          return StreamBuilder<bool>(
            stream: tripRepo.hasUserRated(ref.read(authProvider)?.userId ?? '', widget.tripId),
            builder: (context, ratedSnapshot) {
              final hasRated = ratedSnapshot.data ?? false;

              if (hasRated) {
                return _buildRatedView();
              }

              if (trip.status == 'completed') {
                return _buildCompletedView(trip);
              }

              return Stack(
                children: [
                  _buildMapView(trip),
                  // Notification flottante si accepté ou démarré
                  if (trip.status == 'accepted')
                    Positioned(
                      top: 20, left: 20, right: 20,
                      child: _buildStatusBanner("Chauffeur trouvé ! Il arrive.", Colors.green),
                    ),
                  if (trip.status == 'departed')
                    Positioned(
                      top: 20, left: 20, right: 20,
                      child: _buildStatusBanner("Trajet démarré ! Préparez-vous.", TranSenColors.primaryGreen),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildDriverInfoPanel(trip),
                  ),
                  // --- NOUVEAU : BOUTON SOS ---
                  if (trip.status == 'accepted' || trip.status == 'departed')
                    Positioned(
                      top: 100,
                      right: 20,
                      child: FloatingActionButton.extended(
                        onPressed: () => launchUrl(Uri.parse("tel:17")), // Police Secours Sénégal
                        label: const Text("SOS", style: TextStyle(fontWeight: FontWeight.bold)),
                        icon: const Icon(Icons.warning_amber),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              );
            }
          );
        },
      ),
    );
  }

  Widget _buildSearchingView(TripModel trip) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          lottie.Lottie.network(
            'https://assets10.lottiefiles.com/packages/lf20_mbye9igt.json', // Radar / Searching animation
            width: 200,
            height: 200,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: SizedBox(
                width: 100, height: 100,
                child: CircularProgressIndicator(color: TranSenColors.primaryGreen),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Recherche d'un chauffeur...",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            "Votre demande a été publiée pour votre trajet.",
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 40),
          OutlinedButton(
            onPressed: () => _cancelTrip(trip),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("ANNULER LA DEMANDE"),
          ),
        ],
      ),
    );
  }

  void _cancelTrip(TripModel trip) async {
    if (trip.status == 'accepted' && trip.scheduledDate != null) {
      // Vérification 6h
      try {
        // Format attendu: dd/MM/yyyy HH:mm
        final parts = trip.scheduledDate!.split(' ');
        final datePart = parts[0];
        final timePart = parts.length > 1 ? parts[1] : "08:00";
        
        final dateParts = datePart.split('/');
        final timeParts = timePart.split(':');
        
        final scheduledDateTime = DateTime(
          int.parse(dateParts[2]),
          int.parse(dateParts[1]),
          int.parse(dateParts[0]),
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );

        final now = DateTime.now();
        final difference = scheduledDateTime.difference(now);

        if (difference.inHours < 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Action impossible : Vous ne pouvez pas annuler moins de 6h avant le départ."),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint("Erreur parsing date: $e");
      }
    }

    // Confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler cette course ?"),
        content: const Text("Êtes-vous sûr de vouloir supprimer votre demande ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NON")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OUI, ANNULER", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final userId = ref.read(authProvider)?.userId ?? '';
      await ref.read(tripRepositoryProvider).cancelTrip(trip.id, userId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Demande annulée avec succès."), backgroundColor: Colors.green),
        );
      }
    }
  }

  Widget _buildMapView(TripModel trip) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('active_drivers').doc(trip.driverId).snapshots(),
      builder: (context, driverSnapshot) {
        if (driverSnapshot.hasData && driverSnapshot.data!.exists) {
          final data = driverSnapshot.data!.data() as Map<String, dynamic>;
          final pos = gmaps.LatLng(data['lat'], data['lng']);
          
          _markers.clear();
          _markers.add(gmaps.Marker(
            markerId: const gmaps.MarkerId('driver'),
            position: pos,
            icon: _carIcon ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(gmaps.BitmapDescriptor.hueOrange),
            infoWindow: const gmaps.InfoWindow(title: 'Votre chauffeur'),
          ));

          if (_myPosition != null && !_isRoutePlotted) {
            _getPolyline(pos, _myPosition!);
          }

          if (!_isRoutePlotted) {
            _mapController?.animateCamera(gmaps.CameraUpdate.newLatLng(pos));
          } else {
             // If route plotted, animate camera to fit both
             if (_myPosition != null) {
               _mapController?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(
                 gmaps.LatLngBounds(
                   southwest: gmaps.LatLng(
                     pos.latitude < _myPosition!.latitude ? pos.latitude : _myPosition!.latitude,
                     pos.longitude < _myPosition!.longitude ? pos.longitude : _myPosition!.longitude,
                   ),
                   northeast: gmaps.LatLng(
                     pos.latitude > _myPosition!.latitude ? pos.latitude : _myPosition!.latitude,
                     pos.longitude > _myPosition!.longitude ? pos.longitude : _myPosition!.longitude,
                   ),
                 ),
                 50.0,
               ));
             }
          }
        }

        return gmaps.GoogleMap(
          initialCameraPosition: const gmaps.CameraPosition(target: gmaps.LatLng(14.7167, -17.4677), zoom: 14),
          onMapCreated: (controller) async {
            _mapController = controller;
            if (_myPosition != null) {
              _mapController?.animateCamera(
                gmaps.CameraUpdate.newLatLng(_myPosition!),
              );
            }
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          trafficEnabled: true,
        );
      },
    );
  }

  Widget _buildStatusBanner(String message, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.24), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDriverInfoPanel(TripModel trip) {
    if (trip.driverId == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('users').doc(trip.driverId).snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('active_drivers').doc(trip.driverId).snapshots(),
          builder: (context, activeSnapshot) {
            // --- Caching Logic ---
            String driverName = trip.driverName ?? "Chauffeur TranSen";
            String driverPhone = trip.driverPhone ?? "";

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final data = userSnapshot.data!.data() as Map<String, dynamic>;
              final firstName = data['firstName'];
              final lastName = data['lastName'];
              if (firstName != null && lastName != null) {
                driverName = "$firstName $lastName";
              } else {
                driverName = data['name'] ?? driverName;
              }
              if (data['phone'] != null) driverPhone = data['phone'];
            }

            if (activeSnapshot.hasData && activeSnapshot.data!.exists) {
              final activeData = activeSnapshot.data!.data() as Map<String, dynamic>;
              if (driverName == "Chauffeur TranSen" || driverName.isEmpty) {
                driverName = activeData['driverName'] ?? driverName;
              }
              if (driverPhone.isEmpty) {
                driverPhone = activeData['driverPhone'] ?? "";
              }
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 5)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- SECTION CLIENT (VOUS) ---
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.person, color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("VOTRE PROFIL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                            Text(trip.clientName ?? "Client TranSen", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ),
                      if (trip.clientPhone != null)
                        Text(trip.clientPhone!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Divider(height: 1),
                  ),

                  // --- SECTION CHAUFFEUR ---
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 25, 
                        backgroundColor: TranSenColors.primaryGreen.withValues(alpha: 0.1), 
                        child: const Icon(Icons.directions_car, color: TranSenColors.primaryGreen)
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("VOTRE CHAUFFEUR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                            Row(
                              children: [
                                Text(driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(width: 5),
                                // --- NOUVEAU : BADGE VÉRIFIÉ ---
                                if (userSnapshot.hasData && (userSnapshot.data!.data() as Map<String, dynamic>?)?['isVerified'] == true)
                                  const Icon(Icons.verified, color: Colors.blue, size: 16),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  trip.status == 'departed' ? "Trajet en cours" : "En route vers vous", 
                                  style: TextStyle(color: trip.status == 'departed' ? TranSenColors.primaryGreen : Colors.green, fontSize: 12, fontWeight: FontWeight.bold)
                                ),
                                const SizedBox(width: 8),
                                Consumer(builder: (context, ref, child) {
                                  final ratingAsync = ref.watch(providers.driverRatingProvider(trip.driverId ?? ''));
                                  return ratingAsync.when(
                                    data: (rating) => InkWell(
                                      onTap: () => DriverReviewsSheet.show(context, trip.driverId!, driverName),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.star, color: Colors.amber, size: 14),
                                          const SizedBox(width: 2),
                                          Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 6),
                                          const Text("Voir avis", style: TextStyle(fontSize: 10, color: Colors.amber, decoration: TextDecoration.underline)),
                                        ],
                                      ),
                                    ),
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, __) => const SizedBox.shrink(),
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (driverPhone.isNotEmpty)
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => launchUrl(Uri.parse("https://wa.me/221${driverPhone.replaceAll(' ', '')}")),
                              icon: const Icon(Icons.chat, color: Colors.green),
                              iconSize: 28,
                            ),
                            IconButton(
                              onPressed: () => launchUrl(Uri.parse("tel:$driverPhone")),
                              icon: const Icon(Icons.phone, color: Colors.blue),
                              iconSize: 28,
                            ),
                          ],
                        ),
                    ],
                  ),
                  
                  // --- NOUVEAU : SECTION CO-VOYAGEURS ---
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'transen').collection('pools').doc(widget.tripId).snapshots(),
                    builder: (context, poolSnap) {
                      if (!poolSnap.hasData || !poolSnap.data!.exists) return const SizedBox.shrink();
                      
                      final poolData = poolSnap.data!.data() as Map<String, dynamic>;
                      final passengerDetails = (poolData['passengerDetails'] as Map<String, dynamic>?) ?? {};
                      final currentUserId = ref.read(authProvider)?.userId;
                      
                      // Filtrer pour ne garder que les autres passagers
                      final otherPassengers = passengerDetails.entries
                          .where((entry) => entry.key != currentUserId)
                          .toList();

                      if (otherPassengers.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(height: 1),
                          ),
                          const Text(
                            "VOS CO-VOYAGEURS", 
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: otherPassengers.map((entry) {
                                final p = entry.value as Map<String, dynamic>;
                                String name = p['name'] ?? "Passager";
                                if (p['firstName'] != null) {
                                  name = "${p['firstName']} ${p['lastName'] ?? ''}";
                                }
                                
                                return Padding(
                                  padding: const EdgeInsets.only(right: 15),
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                                        child: Text(
                                          name.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        name.split(' ').first,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  
                  const Divider(height: 35),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDetailItem(Icons.payments, "10 000 FCFA"),
                      _buildDetailItem(Icons.timer, trip.status == 'departed' ? "Arrivée bientôt" : "5-10 min"),
                      TextButton(
                        onPressed: () => _cancelTrip(trip),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text("ANNULER", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 20),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCompletedView(TripModel trip) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            lottie.Lottie.network(
              'https://assets10.lottiefiles.com/packages/lf20_mbye9igt.json',
              width: 200,
              height: 200,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.check_circle, size: 80, color: Colors.green),
            ),
            const SizedBox(height: 20),
            const Text(
              "Course Terminée ! 🏁",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Merci d'avoir utilisé TranSen. Nous espérons que votre trajet a été agréable.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => RatingDialog(tripId: trip.id, driverId: trip.driverId),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: TranSenColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              child: const Text("NOTER MON CHAUFFEUR", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("RETOUR À L'ACCUEIL", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, color: Colors.red, size: 80),
          const SizedBox(height: 20),
          const Text("Merci pour votre avis !", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
            child: const Text("RETOUR"),
          ),
        ],
      ),
    );
  }
}
