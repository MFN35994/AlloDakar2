
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_maps/transen_maps.dart';
import 'package:transen_trips/transen_trips.dart';

import 'package:transen_rating/transen_rating.dart';
import 'dart:ui' show ImageFilter;


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
    _carIcon = await MapMarkerUtils.getCarIcon();
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
          final currentUserId = ref.watch(authProvider)?.userId;

          // Si le trajet n'existe plus ou si l'utilisateur n'est plus dedans (cas annulation pool)
          bool isParticipant = true;
          if (trip != null && trip.type.contains('Covoiturage')) {
            final pIds = (trip.passengerDetails as Map?)?.keys.toList() ?? [];
            if (currentUserId != null && !pIds.contains(currentUserId)) {
              isParticipant = false;
            }
          }

          if (trip == null || !isParticipant) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.search_off, size: 60, color: Colors.grey),
                   const SizedBox(height: 10),
                   const Text("Demande introuvable ou annulée.", style: TextStyle(fontWeight: FontWeight.bold)),
                   const SizedBox(height: 20),
                   ElevatedButton(
                     onPressed: () => Navigator.pop(context), 
                     style: ElevatedButton.styleFrom(backgroundColor: TranSenColors.primaryGreen, foregroundColor: Colors.white),
                     child: const Text("RETOUR À L'ACCUEIL")
                   ),
                ],
              ),
            );
          }

          if (trip.status == 'pending' || trip.status == 'open' || trip.status == 'full') {
            return _buildSearchingView(trip);
          }

          return StreamBuilder<bool>(
            stream: ref.watch(ratingRepositoryProvider).hasUserRated(ref.read(authProvider)?.userId ?? '', widget.tripId),
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
                  DraggableScrollableSheet(
                    initialChildSize: 0.45,
                    minChildSize: 0.3,
                    maxChildSize: 0.7,
                    builder: (context, scrollController) {
                      return _buildDriverInfoPanel(trip, scrollController);
                    },
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
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade600),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverInfoPanel(TripModel trip, ScrollController scrollController) {
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

            final isDark = Theme.of(context).brightness == Brightness.dark;
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 5,
                      )
                    ],
                  ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  // Barre de glissement
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  // --- SECTION CLIENTS (PASSAGERS) ---
                  if (trip.passengerDetails != null && trip.passengerDetails!.isNotEmpty) ...[
                    ...trip.passengerDetails!.entries.map((entry) {
                      final pId = entry.key;
                      final pData = entry.value as Map<String, dynamic>;
                      final pName = pData['name'] ?? "Passager";
                      final pPhone = pData['phone'] as String?;
                      final pMethod = pData['paymentMethod'] ?? "ESPECES";
                      final isMe = pId == ref.watch(authProvider)?.userId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: (isMe ? TranSenColors.primaryGreen : Colors.blue).withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Icon(Icons.person, color: isMe ? TranSenColors.primaryGreen : Colors.blue, size: 20),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isMe ? "VOTRE PROFIL" : "PASSAGER", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                                  Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text("Paiement: ${pMethod.toUpperCase()}", style: const TextStyle(fontSize: 10, color: TranSenColors.primaryGreen, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            if (!isMe && pPhone != null)
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => DeviceUtils.launchWhatsApp(pPhone),
                                    icon: const Icon(Icons.message_outlined, color: Colors.green, size: 22),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 12),
                                  const SizedBox(width: 12),
                                  // Chat entre passagers désactivé pour la confidentialité
                                  const SizedBox(width: 12),
                                  IconButton(
                                    onPressed: () => DeviceUtils.launchPhoneCall(pPhone),
                                    icon: const Icon(Icons.phone, color: Colors.blue, size: 22),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    // Trajet simple
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
                              Text(trip.clientId == ref.watch(authProvider)?.userId ? "VOTRE PROFIL" : "VOTRE CLIENT", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                              Text(trip.clientName ?? "Client TranSen", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        ),
                        if (trip.clientId != ref.watch(authProvider)?.userId && trip.clientPhone != null)
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => DeviceUtils.launchWhatsApp(trip.clientPhone!),
                                icon: const Icon(Icons.message_outlined, color: Colors.green, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        tripId: widget.tripId,
                                        otherPartyName: trip.clientName ?? 'Client',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.chat_bubble_outline, color: TranSenColors.primaryGreen, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                onPressed: () => DeviceUtils.launchPhoneCall(trip.clientPhone!),
                                icon: const Icon(Icons.phone, color: Colors.blue, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          )
                        else if (trip.clientPhone != null)
                          Text(trip.clientPhone!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(height: 1, thickness: 0.5),
                  ),

                  // --- SECTION PROGRESSION ---
                  if (trip.status == 'accepted' || trip.status == 'departed') ...[
                    _buildTripProgress(trip),
                    const SizedBox(height: 25),
                  ],

                  // --- SECTION CHAUFFEUR ---
                  Column(
                    children: [
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
                                Row(
                                  children: [
                                    const Text("VOTRE CHAUFFEUR", 
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)
                                    ),
                                    const Spacer(),
                                    if (trip.status == 'departed')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: TranSenColors.primaryGreen.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text("EN COURSE", style: TextStyle(color: TranSenColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Flexible(child: Text(driverName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5), overflow: TextOverflow.ellipsis)),
                                    const SizedBox(width: 5),
                                    if (userSnapshot.hasData && (userSnapshot.data!.data() as Map<String, dynamic>?)?['isVerified'] == true)
                                      const Icon(Icons.verified, color: Colors.blue, size: 18),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(
                                        color: trip.status == 'departed' ? TranSenColors.primaryGreen : Colors.amber,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      trip.status == 'departed' ? "En déplacement" : "Arrive vers vous", 
                                      style: TextStyle(color: trip.status == 'departed' ? TranSenColors.primaryGreen : Colors.amber.shade700, fontSize: 12, fontWeight: FontWeight.w600)
                                    ),
                                    const SizedBox(width: 12),
                                    Consumer(builder: (context, ref, child) {
                                      final ratingAsync = ref.watch(driverRatingProvider(trip.driverId ?? ''));
                                      return ratingAsync.when(
                                        data: (rating) => InkWell(
                                          onTap: () => DriverReviewsSheet.show(context, trip.driverId!, driverName),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                              const SizedBox(width: 2),
                                              Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                        ],
                      ),
                      
                      if (driverPhone.isNotEmpty && trip.driverId != ref.watch(authProvider)?.userId) ...[
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildActionButton(
                              icon: Icons.message_outlined, 
                              color: Colors.green, 
                              label: "WhatsApp", 
                              onTap: () => DeviceUtils.launchWhatsApp(driverPhone)
                            ),
                            _buildActionButton(
                              icon: Icons.chat_bubble_outline, 
                              color: TranSenColors.primaryGreen, 
                              label: "Chat", 
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      tripId: widget.tripId,
                                      otherPartyName: trip.driverName ?? 'Chauffeur',
                                      passengerId: ref.read(authProvider)?.userId,
                                    ),
                                  ),
                                );
                              }
                            ),
                            _buildActionButton(
                              icon: Icons.phone, 
                              color: Colors.blue, 
                              label: "Appeler", 
                              onTap: () => DeviceUtils.launchPhoneCall(driverPhone)
                            ),
                          ],
                        ),
                      ],

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, thickness: 0.5),
                      ),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Paiement sécurisé",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                const Text(
                                  "ESPÈCES AU CHAUFFEUR",
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TranSenColors.primaryGreen),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      if ((trip.clientId == ref.watch(authProvider)?.userId || 
                          (trip.passengerDetails != null && trip.passengerDetails!.containsKey(ref.watch(authProvider)?.userId))) 
                          && trip.driverId != null) ...[
                        const SizedBox(height: 15),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final myId = ref.read(authProvider)?.userId;
                              if (myId == null) return;
                              await ref.read(favoritesRepositoryProvider).addFavoriteDriver(
                                myId,
                                trip.driverId!,
                                trip.driverName ?? "Chauffeur",
                                trip.driverPhone ?? "",
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Chauffeur ajouté aux favoris !"), backgroundColor: Colors.blue),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.favorite, size: 18),
                          label: const Text("AJOUTER LE CHAUFFEUR AUX FAVORIS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const Divider(height: 35),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDetailItem(Icons.payments, "${(trip.price).toInt()} FCFA"),
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
            ),
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

  Widget _buildTripProgress(TripModel trip) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("DÉPART", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text(trip.departure.split(',').first, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text("DESTINATION", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                Text(trip.destination.split(',').first, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(seconds: 1),
              height: 4,
              width: MediaQuery.of(context).size.width * (trip.status == 'departed' ? 0.6 : 0.2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [TranSenColors.primaryGreen, Colors.blueAccent],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

}
