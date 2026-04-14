import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/models/trip_model.dart';
import '../../domain/models/pool_model.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/trip_providers.dart';
import '../../domain/providers/pool_providers.dart';
import 'trip_detail_screen.dart';
import 'pool_detail_screen.dart';
import 'destination_pools_screen.dart';
import '../widgets/profile_drawer.dart';

final pendingTripsProvider = StreamProvider.family<List<TripModel>, Map<String, String?>>((ref, filters) {
  return ref.watch(tripRepositoryProvider).getPendingTrips(
    departure: filters['departure'],
    destination: filters['destination'],
  );
});

final driverRouteStreamProvider = StreamProvider.family<DocumentSnapshot, String>((ref, driverId) {
  return ref.watch(tripRepositoryProvider).getDriverRoute(driverId);
});

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(14.7167, -17.4677),
    zoom: 13.0,
  );

  GoogleMapController? _mapController;
  bool _isOnline = false;
  Timer? _locationTimer;
  String? _currentDriverId;
  String? _pubDeparture;
  String? _pubDestination;
  bool _isAutoFull = false;
  final Set<String> _ignoredPoolIds = {}; 

  final List<String> _regions = [
    'Dakar', 'Diourbel', 'Fatick', 'Kaffrine', 'Kaolack', 'Kédougou', 'Kolda',
    'Louga', 'Matam', 'Saint-Louis', 'Sédhiou', 'Tambacounda', 'Thiès', 'Ziguinchor',
  ];

  @override
  void dispose() {
    _locationTimer?.cancel();
    // Marquer comme hors ligne à la fermeture
    if (_isOnline && _currentDriverId != null) {
      FirebaseFirestore.instance
          .collection('active_drivers')
          .doc(_currentDriverId)
          .delete();
    }
    super.dispose();
  }

  void _toggleOnline(bool val, String driverId) async {
    _currentDriverId = driverId;
    if (val) {
      // 1. Vérifier si le service de localisation est activé
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Veuillez activer la localisation sur votre téléphone.")),
          );
        }
        return;
      }

      // 2. Vérifier les permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permission de localisation refusée. Veuillez l'activer dans les paramètres.")),
          );
        }
        return;
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        // Récupérer les infos du profil une seule fois
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(driverId).get();
        final userData = userDoc.data();
        final name = userData?['name'] ?? 'Chauffeur Allô Dakar';
        final phone = userData?['phone'] ?? '';

        setState(() => _isOnline = true);
        _startLocationUpdates(driverId, name, phone);
      }
    } else {
      setState(() {
        _isOnline = false;
        _isAutoFull = false; // Reset auto-full
      });
      _locationTimer?.cancel();
      // Supprimer le marqueur actif
      await FirebaseFirestore.instance
          .collection('active_drivers')
          .doc(driverId)
          .delete();
    }
  }

  void _startLocationUpdates(String driverId, String name, String phone) {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition();
        await FirebaseFirestore.instance
            .collection('active_drivers')
            .doc(driverId)
            .set({
          'lat': position.latitude,
          'lng': position.longitude,
          'lastUpdated': FieldValue.serverTimestamp(),
          'status': 'online',
          'driverName': name,
          'driverPhone': phone,
          'departure': _pubDeparture,
          'destination': _pubDestination,
        });
      } catch (e) {
        debugPrint("Erreur update position: $e");
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final currentUserId = auth?.userId ?? 'unknown_driver';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Espace Chauffeur'),
            const SizedBox(width: 5),
            Consumer(builder: (context, ref, child) {
              final auth = ref.watch(authProvider);
              if (auth == null) return const SizedBox.shrink();
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(auth.userId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && (snapshot.data!.data() as Map<String, dynamic>?)?['isVerified'] == true) {
                    return const Icon(Icons.verified, color: Colors.blue, size: 18);
                  }
                  return const SizedBox.shrink();
                },
              );
            }),
          ],
        ),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Row(
            children: [
              Text(
                _isOnline ? 'En Ligne' : 'Hors Ligne',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? Colors.greenAccent : Colors.white54,
                ),
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: Colors.greenAccent,
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white24,
                onChanged: (val) => _toggleOnline(val, currentUserId),
              ),
            ],
          ),
        ],
      ),
      drawer: const ProfileDrawer(),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                GoogleMap(
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
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  zoomControlsEnabled: false,
                ),
                // Floating Action Button pour la position géographique au-dessus du panel
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton(
                    onPressed: () {
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(_initialPosition),
                      );
                    },
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          
          // Moitié Basse : Dashboard Chauffeur
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA), // Off-white très premium
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000), // Hex equivalent factor for 0.08 opacity
                    blurRadius: 30,
                    spreadRadius: 5,
                    offset: Offset(0, -10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                // === NOUVEAU: COURSE EN COURS ===
                if (_isOnline)
                  Consumer(builder: (context, ref, child) {
                    final activeTripAsync = ref.watch(driverActivePoolProvider);
                    return activeTripAsync.when(
                      data: (pool) {
                        if (pool == null) return const SizedBox.shrink();
                        return _buildActiveDriverTripCard(context, pool);
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  }),

                // Bloc Route du Jour (Matching Intelligent)
                if (_isOnline) ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.orange, size: 20),
                            SizedBox(width: 10),
                            Text("Mon trajet d'aujourd'hui", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  hint: const Text("Départ"),
                                  value: _pubDeparture,
                                  isExpanded: true,
                                  items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                  onChanged: (val) {
                                    setState(() => _pubDeparture = val);
                                    // Toujours publier la route, même si destination est nulle (pour filtrage origine)
                                    ref.read(tripRepositoryProvider).publishDriverRoute(currentUserId, val!, _pubDestination);
                                  },
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                            const SizedBox(width: 5),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  hint: const Text("Arrivée"),
                                  value: _pubDestination,
                                  isExpanded: true,
                                  items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                  onChanged: (val) {
                                    setState(() => _pubDestination = val);
                                    if (_pubDeparture != null) {
                                      ref.read(tripRepositoryProvider).publishDriverRoute(currentUserId, _pubDeparture!, val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // --- NOUVEAU : CARTES DE CHALEUR ET OPTIONS POOLING ---
                if (_isOnline) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Zones de forte demande", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        TextButton.icon(
                          onPressed: () => setState(() => _isAutoFull = !_isAutoFull),
                          icon: Icon(_isAutoFull ? Icons.flash_on : Icons.flash_off, size: 16, color: _isAutoFull ? Colors.orange : Colors.grey),
                          label: Text(_isAutoFull ? "AUTO-FULL ACTIVÉ" : "AUTO-FULL DÉSACTIVÉ", style: TextStyle(fontSize: 10, color: _isAutoFull ? Colors.orange : Colors.grey)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 50,
                    child: Consumer(builder: (context, ref, child) {
                      final heatmapAsync = ref.watch(demandHeatmapProvider);
                      return heatmapAsync.when(
                        data: (heatmap) {
                          if (heatmap.isEmpty) return const Center(child: Text("Aucune demande en attente.", style: TextStyle(fontSize: 12, color: Colors.grey)));
                          final sortedEntries = heatmap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: sortedEntries.length,
                            itemBuilder: (context, index) {
                              final entry = sortedEntries[index];
                              return InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DestinationPoolsScreen(destination: entry.key),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: entry.value > 5 ? 0.2 : 0.05),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "${entry.key} (${entry.value} pers.)",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                ],

                // Bloc Gain Journalier
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // COMMENTÉ POUR LANCEMENT GRATUIT
                          // Expanded(
                          //   child: Column(
                          //     crossAxisAlignment: CrossAxisAlignment.start,
                          //     children: [
                          //       Text(
                          //         "Mon Portefeuille",
                          //         style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
                          //       ),
                          //       const SizedBox(height: 5),
                          //       Consumer(builder: (context, ref, child) {
                          //         final wallet = ref.watch(walletProvider);
                          //         return Text(
                          //           "${wallet.balance.toInt()} FCFA",
                          //           style: TextStyle(
                          //             fontSize: 24,
                          //             fontWeight: FontWeight.w900,
                          //             color: _isOnline ? Colors.green.shade700 : Colors.grey.shade400,
                          //           ),
                          //         );
                          //       }),
                          //     ],
                          //   ),
                          // ),
                          const Expanded(child: SizedBox()), // Remplacé provisoirement
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Consumer(builder: (context, ref, child) {
                              final ratingAsync = ref.watch(driverRatingProvider(currentUserId));
                              return ratingAsync.when(
                                data: (rating) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                loading: () => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
                                error: (_, __) => const Icon(Icons.star, color: Colors.grey, size: 16),
                              );
                            }),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 15),
                      
                      // Indicateur Covoiturage (4 places) - Placé en dessous pour éviter overflow
                      Consumer(builder: (context, ref, child) {
                        final occupancy = ref.watch(driverOccupancyProvider(currentUserId));
                        return occupancy.when(
                          data: (pCount) => Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            decoration: BoxDecoration(
                              color: (pCount >= 4 ? Colors.red : Colors.green).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.groups, color: pCount >= 4 ? Colors.red : Colors.green, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "$pCount / 4 places occupées ${pCount >= 4 ? '(Complet !)' : ''}",
                                    style: TextStyle(
                                      fontSize: 13, 
                                      fontWeight: FontWeight.bold,
                                      color: pCount >= 4 ? Colors.red : Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      }),
                    ],
                  ),
                ),
                
                // --- NOUVEAU : LIVRAISONS YOBANTÉ ---
                if (_isOnline)
                  Consumer(
                    builder: (context, ref, child) {
                      final deliveriesAsync = ref.watch(pendingTripsProvider({
                        'departure': _pubDeparture,
                        'destination': _pubDestination,
                      }));

                      return deliveriesAsync.when(
                        data: (trips) {
                          // Filtrer pour ne garder que les colis/yobante
                          final deliveries = trips.where((t) => 
                            t.type.toLowerCase().contains('livraison') || 
                            t.type.toLowerCase().contains('colis')
                          ).toList();

                          debugPrint("[YOBANTE] Trips reçus: ${trips.length}, Filtrés (colis): ${deliveries.length}");
                          if (deliveries.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Livraisons Yobanté à proximité",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text(
                                      "${deliveries.length} dispo.",
                                      style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 160,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  itemCount: deliveries.length,
                                  itemBuilder: (context, index) {
                                    final delivery = deliveries[index];
                                    return _buildDeliverySmallCard(context, delivery);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      );
                    },
                  ),

                // Liste des commandes dynamiques Firebase
                _isOnline 
                ? Consumer(
                        builder: (context, ref, child) {
                          final poolsAsyncValue = ref.watch(pendingPoolsProvider(
                            "${_pubDeparture ?? 'ANY'}|${_pubDestination ?? 'ANY'}"
                          ));
                          
                          return poolsAsyncValue.when(
                            data: (pools) {
                              if (pools.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(40.0),
                                    child: Text(
                                      _pubDeparture == null ? 'Sélectionnez un trajet pour voir les covoiturages.' : 'Aucun groupe de voyageur pour le moment.', 
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  ),
                                );
                              }
                              
                              // Tri Auto-Full : Les 4/4 en premier si l'option est activée
                              final sortedPools = pools.where((p) => !_ignoredPoolIds.contains(p.id)).toList();
                              if (_isAutoFull) {
                                sortedPools.sort((a, b) => b.currentFilling.compareTo(a.currentFilling));
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                                itemCount: sortedPools.length + 1,
                                separatorBuilder: (context, index) => const SizedBox(height: 15),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Groupes à destination',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        if (_isAutoFull)
                                          const Icon(Icons.flash_on, color: Colors.orange, size: 16),
                                      ],
                                    );
                                  }
                                  final pool = sortedPools[index - 1];
                                  return _buildPoolCard(
                                    pool: pool,
                                    driverId: currentUserId,
                                  );
                                },
                              );
                            },
                            loading: () => const Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
                            error: (err, stack) => Center(child: Text('Erreur: $err')),
                          );
                        },
                      )
                  : Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new, size: 60, color: Colors.grey.shade300),
                          const SizedBox(height: 15),
                          Text(
                            'Vous êtes hors ligne',
                            style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Passez en ligne pour recevoir des courses.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
              ],
             ),
            ),
           ),
          ),
         ),
        ],
      ),
    );
  }

  Widget _buildPoolCard({required PoolModel pool, required String driverId}) {
    final canAcceptAt3 = pool.currentFilling >= 3;
    final isFull = pool.currentFilling >= 4;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Trajet ${pool.departure} ➔ ${pool.destination}",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Prévu pour le: ${pool.scheduledDate}",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (isFull)
                   const Icon(Icons.check_circle, color: Colors.green, size: 24)
                else ...[
                   if (canAcceptAt3) const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                   IconButton(
                     icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                     onPressed: () => setState(() => _ignoredPoolIds.add(pool.id)),
                   ),
                ],
              ],
            ),
            const SizedBox(height: 15),
            
            // Barre de progression simplifiée
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: pool.currentFilling / 4,
                backgroundColor: Colors.grey.shade100,
                color: isFull ? Colors.green : Colors.orange,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${pool.currentFilling}/4 passagers", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                if (canAcceptAt3 && !isFull)
                  const Text("Acceptable (3/4)", style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(height: 1, color: Colors.black12),
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total (estimé)", style: TextStyle(fontWeight: FontWeight.bold)),
                Text("${pool.currentFilling * 10000} FCFA", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green)),
              ],
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                      try {
                        // 0. Confirmation si peu de passagers
                        if (pool.currentFilling < 3) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Départ anticipé ?"),
                              content: Text("Il n'y a que ${pool.currentFilling} passager(s). Voulez-vous quand même accepter ce trajet ?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ANNULER")),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("OUI, ACCEPTER")),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                        }

                        // 1. Commission 5% (COMMENTÉ POUR LE LANCEMENT GRATUIT)
                        // final totalCommission = pool.currentFilling * 500;
                        // final wallet = ref.read(walletProvider);
                        // if (wallet.balance < totalCommission) {
                        //   throw Exception("Solde insuffisant pour la commission ($totalCommission FCFA)");
                        // }

                        // ... le reste est identique
                        await ref.read(tripRepositoryProvider).acceptPool(pool.id, driverId);
                        // ref.read(walletProvider.notifier).credit((pool.currentFilling * 10000).toDouble(), 'Gains Covoiturage ${pool.destination}');
                        // ref.read(walletProvider.notifier).debit(totalCommission.toDouble(), 'Commission Plateforme (5%)');
                        
                        if (mounted) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PoolDetailScreen(pool: pool)));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFull ? Colors.green : (canAcceptAt3 ? Colors.orange : Colors.black87),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  isFull ? 'DÉPART IMMÉDIAT (COMPLET)' : (canAcceptAt3 ? 'ACCEPTER (3/4)' : 'ACCEPTER (${pool.currentFilling}/4)'), 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDriverTripCard(BuildContext context, PoolModel pool) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade800, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PoolDetailScreen(pool: pool)));
          },
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.airport_shuttle, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Course Active !",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${pool.departure} ➔ ${pool.destination}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pool.status == 'departed' ? "Trajet en cours" : "En route vers le point de collecte",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeliverySmallCard(BuildContext context, TripModel delivery) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(trip: delivery)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2, color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delivery.departure,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.arrow_downward, size: 12, color: Colors.grey),
            ),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    delivery.destination,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  delivery.type.split('(').last.replaceAll(')', ''),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                const Text(
                  "10 000 F",
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
