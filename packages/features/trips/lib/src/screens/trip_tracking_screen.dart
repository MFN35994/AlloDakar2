
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:transen_core/transen_core.dart';
import 'package:transen_auth/transen_auth.dart';
import 'package:transen_maps/transen_maps.dart';
import 'package:transen_trips/transen_trips.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import 'package:transen_rating/transen_rating.dart';
import 'dart:ui' as ui;


class TripTrackingScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripTrackingScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends ConsumerState<TripTrackingScreen> {
  MapboxMap? _mapController;
  PointAnnotationManager? _annotationManager;
  Uint8List? _carIconBytes;
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
      geo.Position pos = await geo.Geolocator.getCurrentPosition();
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
      final dio = Dio();
      const String mapboxToken = "pk.eyJ1IjoidHJhbnNlbiIsImEiOiJjbXA4Nm5menUwM205MnNwOGZmb3N3ZTM4In0.SMFaXkbJJi5bM6Bk3_p8ng";
      final url = "https://api.mapbox.com/directions/v5/mapbox/driving/${driverPos.longitude},${driverPos.latitude};${clientPos.longitude},${clientPos.latitude}?overview=full&geometries=geojson&access_token=$mapboxToken";
      
      final response = await dio.get(url);
      
      if (response.statusCode == 200) {
        final data = response.data;
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final route = routes[0];
          final geometry = route['geometry'];
          
          if (_mapController != null) {
            final source = GeoJsonSource(id: "route-source", data: jsonEncode(geometry));
            await _mapController!.style.addSource(source);
            
            final layer = LineLayer(
              id: "route-layer",
              sourceId: "route-source",
              lineColor: Colors.blue.toARGB32(),
              lineWidth: 6.0,
            );
            await _mapController!.style.addLayer(layer);
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur Directions API: $e");
      _isRoutePlotted = false;
    }
  }


  void _loadMarkerIcon() async {
    _carIconBytes = await MapMarkerUtils.getCarIconBytes();
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

          if (trip == null || !isParticipant || trip.status == 'cancelled') {
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
          const SizedBox(
            width: 100, height: 100,
            child: CircularProgressIndicator(color: TranSenColors.primaryGreen),
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
          
          if (_annotationManager != null) {
            _annotationManager!.deleteAll();
            if (_carIconBytes != null) {
              _annotationManager!.create(PointAnnotationOptions(
                geometry: Point(coordinates: Position(pos.longitude, pos.latitude)),
                image: _carIconBytes!,
                iconSize: 1.0,
              ));
            }
          }

          if (_myPosition != null && !_isRoutePlotted) {
            _getPolyline(pos, _myPosition!);
          }

          if (!_isRoutePlotted) {
            _mapController?.setCamera(
              CameraOptions(
                center: Point(coordinates: Position(pos.longitude, pos.latitude)),
                zoom: 15.0,
              ),
            );
          } else {
             // For bounds, we just center on driver for simplicity in Mapbox
             _mapController?.setCamera(
               CameraOptions(
                 center: Point(coordinates: Position(pos.longitude, pos.latitude)),
                 zoom: 13.0,
               ),
             );
          }
        }

        return MapWidget(
          viewport: CameraViewportState(
            center: Point(coordinates: Position(-17.4677, 14.7167)),
            zoom: 14.0,
          ),
          onMapCreated: (MapboxMap mapboxMap) async {
            _mapController = mapboxMap;
            _annotationManager = await mapboxMap.annotations.createPointAnnotationManager();
            if (_myPosition != null) {
              _mapController?.setCamera(
                CameraOptions(
                  center: Point(coordinates: Position(_myPosition!.longitude, _myPosition!.latitude)),
                  zoom: 14.0,
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildStatusBanner(String message, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
                  // --- HEADER GRADIENT (CHAUFFEUR) ---
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [TranSenColors.primaryGreen.withValues(alpha: 0.9), TranSenColors.primaryGreen],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(Icons.directions_car, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  trip.type.contains('Livraison') ? '📦 Livraison Yobanté' : '🚕 Course VTC',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (driverPhone.isNotEmpty)
                          IconButton(
                            onPressed: () => DeviceUtils.launchPhoneCall(driverPhone),
                            style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2)),
                            icon: const Icon(Icons.phone, color: Colors.white),
                          ),
                      ],
                    ),
                  ),

                  // --- SECTION TRAJET ---
                  _SectionCard(
                    children: [
                      _InfoRow(
                        icon: Icons.my_location,
                        iconColor: Colors.blue,
                        label: 'Départ',
                        value: trip.departure,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 11, top: 4, bottom: 4),
                        child: Icon(Icons.more_vert, size: 16, color: Colors.grey),
                      ),
                      _InfoRow(
                        icon: Icons.location_on,
                        iconColor: Colors.red,
                        label: 'Destination',
                        value: trip.destination,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // --- SECTION INFOS COURSE ---
                  _SectionCard(
                    children: [
                      _InfoRow(
                        icon: Icons.category,
                        iconColor: TranSenColors.primaryGreen,
                        label: 'Type',
                        value: trip.type,
                      ),
                      if (trip.scheduledDate != null) ...[
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.calendar_today,
                          iconColor: Colors.orange,
                          label: 'Date prévue',
                          value: trip.scheduledDate!,
                        ),
                      ],
                      if (trip.seats != null) ...[
                        const Divider(height: 20),
                        _InfoRow(
                          icon: Icons.groups,
                          iconColor: TranSenColors.primaryGreen,
                          label: 'Passagers',
                          value: '${trip.seats} personne(s)',
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // --- SECTION PAIEMENT ---
                  _SectionCard(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.payments, color: Colors.green, size: 20),
                              SizedBox(width: 10),
                              Text('Prix', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                          Text(
                            '${trip.price.toInt()} FCFA',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // --- SECTION ACTIONS RAPIDES ---
                  if (driverPhone.isNotEmpty)
                    _SectionCard(
                      children: [
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
                    ),

                  const SizedBox(height: 12),

                  // --- SECTION PASSAGERS (SI COVOITURAGE) ---
                  if (trip.passengerDetails != null && trip.passengerDetails!.isNotEmpty) ...[
                    const Text("Passagers", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ...trip.passengerDetails!.entries.map((entry) {
                      final pData = entry.value as Map<String, dynamic>;
                      final pName = pData['name'] ?? "Passager";
                      final pPhone = pData['phone'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SectionCard(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(pName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (pPhone != null)
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => DeviceUtils.launchWhatsApp(pPhone),
                                        icon: const Icon(Icons.message, color: Colors.green, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: () => DeviceUtils.launchPhoneCall(pPhone),
                                        icon: const Icon(Icons.phone, color: Colors.blue, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 12),

                  // --- BOUTON AJOUTER AUX FAVORIS ---
                  if (trip.driverId != null)
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
                        minimumSize: const ui.Size(double.infinity, 40),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // --- BOUTON ANNULER ---
                  OutlinedButton.icon(
                    onPressed: () => _cancelTrip(trip),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text("ANNULER LA DEMANDE", style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
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



  Widget _buildCompletedView(TripModel trip) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
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

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
